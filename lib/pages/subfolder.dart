import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:focused_menu/focused_menu.dart';
import 'package:focused_menu/modals.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class SubfolderPage extends StatefulWidget {
  final String parentPath;  // path like 'folders/docId/subfolders/docId/...'
  final String folderId;    // ID of the current folder
  final String folderName;  // Display name
  final String? driveFolderId; // Google Drive folder ID

  const SubfolderPage({
    super.key,
    required this.parentPath,
    required this.folderId,
    required this.folderName,
    this.driveFolderId,
  });

  @override
  State<SubfolderPage> createState() => _SubfolderPageState();
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class _SubfolderPageState extends State<SubfolderPage> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  String get currentPath => '${widget.parentPath}/${widget.folderId}/folders';
  bool _isUploadingToDrive = false;
  String _driveUploadStatus = '';

  // Create new subfolder in Firestore
  void _addSubfolder(BuildContext context) {
    final TextEditingController folderNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create New Subfolder"),
        content: TextField(
          controller: folderNameController,
          decoration: const InputDecoration(hintText: "Enter subfolder name"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final folderName = folderNameController.text.trim();
              if (folderName.isEmpty) return;

              // Create folder in Google Drive and get its ID
              final String? driveFolderId = await _createFolderInGoogleDrive(folderName);

              await FirebaseFirestore.instance
                  .collection(currentPath)
                  .doc(DateTime.now().millisecondsSinceEpoch.toString())
                  .set({
                'name': folderName,
                'createdAt': FieldValue.serverTimestamp(),
                'isFolder': true,
                'driveFolderId': driveFolderId, // Store the Google Drive folder ID
              });

              if (!mounted) return;
              Navigator.of(context).pop();
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  // Method to create folder in Google Drive
  Future<String?> _createFolderInGoogleDrive(String folderName) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final authHeaders = {
        'Authorization': 'Bearer ${googleAuth.accessToken}',
      };

      final authenticatedClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticatedClient);

      // Use the parent folder's driveFolderId if available, otherwise create in root
      String? parentFolderId = widget.driveFolderId;
      if (parentFolderId == null) {
        parentFolderId = await _getOrCreateDriveFolder(
            driveApi,
            'DocumentManagerUploads',
            parentId: 'root'
        );
      }

      // Create the folder in Google Drive
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      if (parentFolderId != null) {
        folder.parents = [parentFolderId];
      }

      final createdFolder = await driveApi.files.create(folder);
      return createdFolder.id;
    } catch (e) {
      print('Error creating folder in Drive: $e');
      return null;
    }
  }

  // Handle image selection and upload
  Future<void> _addImage() async {
    if (!mounted) return;

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Select Image Source"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text("Camera"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text("Gallery"),
          ),
        ],
      ),
    );

    if (!mounted || source == null) return;

    try {
      final pickedFile = await ImagePicker().pickImage(source: source);
      if (!mounted || pickedFile == null) return;

      await _uploadToGoogleDrive(File(pickedFile.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  // Get image name from user
  Future<String?> _showImageNameDialog() async {
    final TextEditingController controller = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Name Your Image"),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: "Enter image name (optional)",
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            validator: (value) {
              if (value != null && value.length > 50) {
                return 'Name too long (max 50 characters)';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text("Continue"),
          ),
        ],
      ),
    );
  }

  // Upload to Google Drive with proper folder structure
  Future<void> _uploadToGoogleDrive(File image) async {
    final fileName = await _showImageNameDialog() ??
        'image_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _isUploadingToDrive = true;
      _driveUploadStatus = 'Preparing upload...';
    });

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          _isUploadingToDrive = false;
          _driveUploadStatus = 'Sign-in cancelled';
        });
        return;
      }

      final googleAuth = await googleUser.authentication;
      final authHeaders = {
        'Authorization': 'Bearer ${googleAuth.accessToken}',
      };

      final authenticatedClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticatedClient);

      setState(() {
        _driveUploadStatus = 'Uploading image...';
      });

      // Use the existing driveFolderId if available, otherwise create new folder structure
      String? parentFolderId = widget.driveFolderId;

      if (parentFolderId == null) {
        // Fallback: create folder structure based on folder name
        final rootFolderId = await _getOrCreateDriveFolder(
            driveApi,
            'DocumentManagerUploads',
            parentId: 'root'
        );

        if (rootFolderId == null) throw Exception('Failed to create root folder');

        parentFolderId = await _getOrCreateDriveFolder(
            driveApi,
            widget.folderName,
            parentId: rootFolderId
        );

        if (parentFolderId == null) throw Exception('Failed to create subfolder');
      }

      // Upload the image to the folder
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [parentFolderId];

      final mimeType = lookupMimeType(image.path) ?? 'application/octet-stream';
      final media = drive.Media(
        image.openRead(),
        image.lengthSync(),
        contentType: mimeType,
      );

      final uploadedFile = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
      );

      // Make the file publicly accessible
      final permission = drive.Permission()
        ..type = 'anyone'
        ..role = 'reader';

      await driveApi.permissions.create(permission, uploadedFile.id!);

      // Generate view and download links
      final webViewLink = 'https://drive.google.com/uc?export=view&id=${uploadedFile.id}';
      final downloadLink = 'https://drive.google.com/uc?export=download&id=${uploadedFile.id}';

      // Save to Firestore
      await _storeDriveLinkInFirebase(
        webViewLink,
        downloadLink,
        fileName,
        uploadedFile.id!,
      );

      setState(() {
        _isUploadingToDrive = false;
        _driveUploadStatus = 'Upload complete!';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File uploaded to Google Drive')),
      );
    } catch (e) {
      setState(() {
        _isUploadingToDrive = false;
        _driveUploadStatus = 'Upload failed: ${e.toString()}';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${e.toString()}')),
      );
    }
  }

  // Helper to create or get existing folder
  Future<String?> _getOrCreateDriveFolder(
      drive.DriveApi driveApi,
      String folderName, {
        String? parentId,
      }) async {
    try {
      var query = "mimeType='application/vnd.google-apps.folder' "
          "and name='$folderName' "
          "and trashed=false";

      if (parentId != null) {
        query += " and '$parentId' in parents";
      } else {
        query += " and 'root' in parents";
      }

      final response = await driveApi.files.list(q: query);
      if (response.files!.isNotEmpty) return response.files!.first.id;

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = parentId != null ? [parentId] : ['root'];

      return (await driveApi.files.create(folder)).id;
    } catch (e) {
      print('Error creating folder "$folderName": $e');
      return null;
    }
  }

  // Store Drive links in Firestore
  Future<void> _storeDriveLinkInFirebase(
      String webViewLink,
      String downloadLink,
      String fileName,
      String driveId,
      ) async {
    await FirebaseFirestore.instance
        .collection(currentPath)
        .doc('IMG_${DateTime.now().millisecondsSinceEpoch}')
        .set({
      'name': fileName,
      'createdAt': FieldValue.serverTimestamp(),
      'isFolder': false,
      'webViewLink': webViewLink,
      'downloadLink': downloadLink,
      'type': 'image',
      'driveId': driveId,
    });
  }

  // DELETE FUNCTIONALITY
  Future<void> _deleteItem(String itemId, Map<String, dynamic> itemData) async {
    final bool isFolder = itemData['isFolder'] ?? false;
    final String itemName = itemData['name'] ?? 'Unnamed';
    final String? driveId = itemData['driveId'];
    final String? driveFolderId = itemData['driveFolderId'];

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${isFolder ? 'Folder' : 'File'}'),
        content: Text('Are you sure you want to delete "$itemName"? ${isFolder ? 'This will also delete all contents inside the folder.' : ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      if (isFolder) {
        await _deleteFolderRecursively(itemId, driveFolderId);
      } else {
        await _deleteSingleItem(itemId, driveId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$itemName" deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting: ${e.toString()}')),
      );
    }
  }

  Future<void> _deleteSingleItem(String itemId, String? driveId) async {
    await FirebaseFirestore.instance
        .collection(currentPath)
        .doc(itemId)
        .delete();

    if (driveId != null && driveId.isNotEmpty) {
      await _deleteFromGoogleDrive(driveId);
    }
  }

  Future<void> _deleteFolderRecursively(String folderId, String? driveFolderId) async {
    final folderRef = FirebaseFirestore.instance.collection(currentPath).doc(folderId);
    final subItems = await folderRef.collection('folders').get();

    for (final doc in subItems.docs) {
      final itemData = doc.data();
      final isSubFolder = itemData['isFolder'] ?? false;
      final subDriveFolderId = itemData['driveFolderId'];

      if (isSubFolder) {
        await _deleteFolderRecursively(doc.id, subDriveFolderId);
      } else {
        await _deleteSingleItem(doc.id, itemData['driveId']);
      }
    }

    await folderRef.delete();

    if (driveFolderId != null && driveFolderId.isNotEmpty) {
      await _deleteFromGoogleDrive(driveFolderId);
    }
  }

  Future<void> _deleteFromGoogleDrive(String fileId) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final authHeaders = {
        'Authorization': 'Bearer ${googleAuth.accessToken}',
      };

      final authenticatedClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticatedClient);

      await driveApi.files.delete(fileId);
    } catch (e) {
      print('Error deleting from Drive: $e');
    }
  }

  // RENAME FUNCTIONALITY
  Future<void> _renameItem(String itemId, Map<String, dynamic> itemData) async {
    final bool isFolder = itemData['isFolder'] ?? false;
    final String currentName = itemData['name'] ?? '';
    final String? driveId = itemData['driveId'];
    final String? driveFolderId = itemData['driveFolderId'];

    final TextEditingController nameController = TextEditingController(text: currentName);

    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${isFolder ? 'Folder' : 'File'}'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: "Enter new name"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmedName = nameController.text.trim();
              if (trimmedName.isNotEmpty && trimmedName != currentName) {
                Navigator.of(context).pop(trimmedName);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection(currentPath)
          .doc(itemId)
          .update({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!isFolder && driveId != null) {
        await _renameInGoogleDrive(driveId, newName);
      } else if (isFolder && driveFolderId != null) {
        await _renameInGoogleDrive(driveFolderId, newName);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renamed to "$newName"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error renaming: ${e.toString()}')),
      );
    }
  }

  Future<void> _renameInGoogleDrive(String fileId, String newName) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final authHeaders = {
        'Authorization': 'Bearer ${googleAuth.accessToken}',
      };

      final authenticatedClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticatedClient);

      final driveFile = drive.File()..name = newName;
      await driveApi.files.update(driveFile, fileId);
    } catch (e) {
      print('Error renaming in Drive: $e');
    }
  }

  // Show image preview dialog
  void _showImagePreview(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 3.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Text('Failed to load image'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.folderName),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addSubfolder(context),
          ),
          IconButton(
            onPressed: _addImage,
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection(currentPath).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No items found"));
              }

              return GridView.builder(
                itemCount: snapshot.data!.docs.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  childAspectRatio: 0.75,
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final isFolder = data['isFolder'] ?? false;
                  final name = data['name'] ?? 'Unnamed';
                  final webViewLink = data['webViewLink'];

                  return FocusedMenuHolder(
                    menuWidth: 220,
                    blurSize: 0,
                    blurBackgroundColor: Colors.white,
                    onPressed: (){},
                    menuItems: [
                      FocusedMenuItem(
                        title: const Text("Delete"),
                        onPressed: () => _deleteItem(doc.id, data),
                        trailingIcon: const Icon(Icons.delete_outline),
                      ),
                      FocusedMenuItem(
                        title: const Text("Rename"),
                        onPressed: () => _renameItem(doc.id, data),
                        trailingIcon: const Icon(Icons.drive_file_rename_outline),
                      ),
                    ],
                    child: Column(
                      children: [
                        SizedBox(
                          height: 100,
                          width: 100,
                          child: InkWell(
                            onTap: () {
                              if (isFolder) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SubfolderPage(
                                      parentPath: currentPath,
                                      folderId: doc.id,
                                      folderName: name,
                                      driveFolderId: data['driveFolderId'],
                                    ),
                                  ),
                                );
                              } else if (webViewLink != null) {
                                _showImagePreview(context, webViewLink);
                              }
                            },
                            child: isFolder
                                ? Image.asset("assets/efolder.jpg")
                                : webViewLink != null
                                ? Image.network(
                              webViewLink,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: progress.expectedTotalBytes != null
                                        ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                        : null,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) =>
                                  Image.asset("assets/efile.png"),
                            )
                                : Image.asset("assets/efile.png"),
                          ),
                        ),
                        Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          if (_isUploadingToDrive)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(_driveUploadStatus),
                ],
              ),
            ),
        ],
      ),
    );
  }
}