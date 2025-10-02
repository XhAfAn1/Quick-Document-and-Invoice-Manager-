import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:document_manager/pages/subfolder.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:focused_menu/focused_menu.dart';
import 'package:focused_menu/modals.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import '../authentication/signin.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/drive.appdata',
    ],
    hostedDomain: '', // Important for personal accounts
  );

  bool _isUploadingToDrive = false;
  String _driveUploadStatus = '';

  void _addRootFolder(BuildContext context) async {
    final TextEditingController folderNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create New Folder"),
        content: TextField(
          controller: folderNameController,
          decoration: const InputDecoration(hintText: "Enter folder name"),
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

              final user = FirebaseAuth.instance.currentUser!;
              final userDoc = FirebaseFirestore.instance.collection("folders").doc(user.uid);

              await userDoc.set({
                'userName': user.displayName ?? 'User',
                'email': user.email ?? 'Email',
                'createdAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

              // Create folder in Google Drive and get its ID
              final String? driveFolderId = await _createFolderInGoogleDrive(folderName);

              await userDoc.collection('folders').doc(DateTime.now().millisecondsSinceEpoch.toString()).set({
                'name': folderName,
                'createdAt': FieldValue.serverTimestamp(),
                'isFolder': true,
                'driveFolderId': driveFolderId, // Store the Google Drive folder ID
              });

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

      // Get the root folder ID
      String? parentFolderId = await _getOrCreateAppRootFolder(driveApi);

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

  void _signOut() async {
    await FirebaseAuth.instance.signOut();
    await _googleSignIn.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => SignInPage()),
          (route) => false,
    );
  }

  Future<void> _addImage() async {
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

    if (source == null) return;

    try {
      final pickedFile = await ImagePicker().pickImage(source: source);
      if (pickedFile == null) return;

      final user = FirebaseAuth.instance.currentUser!;
      final firebasePath = 'folders/${user.uid}/folders';

      await _uploadToGoogleDrive(File(pickedFile.path), firebasePath);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

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
              helperText: "Leave empty for auto-generated name",
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

  // DELETE FUNCTIONALITY - FIXED FOR FOLDERS
  Future<void> _deleteItem(String itemId, Map<String, dynamic> itemData, String parentPath) async {
    final bool isFolder = itemData['isFolder'] ?? false;
    final String itemName = itemData['name'] ?? 'Unnamed';
    final String? driveId = itemData['driveId'];
    final String? driveFolderId = itemData['driveFolderId'];

    // Show confirmation dialog
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${isFolder ? 'Folder' : 'File'}'),
        content: Text('Are you sure you want to delete "$itemName"? ${isFolder ? 'This will also delete all contents inside the folder.' : ''} This action cannot be undone.'),
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
        // Delete folder recursively (including all contents)
        await _deleteFolderRecursively(itemId, parentPath, driveFolderId);
      } else {
        // Delete single file
        await _deleteSingleItem(itemId, itemData, parentPath);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$itemName" deleted successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting: ${e.toString()}')),
      );
    }
  }

  // DELETE SINGLE ITEM (FILE)
  Future<void> _deleteSingleItem(String itemId, Map<String, dynamic> itemData, String parentPath) async {
    final String? driveId = itemData['driveId'];

    // Delete from Firebase
    final docRef = _getDocumentReference(itemId, parentPath);
    await docRef.delete();

    // If it's a file and has a driveId, delete from Google Drive too
    if (driveId != null && driveId.isNotEmpty) {
      await _deleteFromGoogleDrive(driveId);
    }
  }

  // DELETE FOLDER RECURSIVELY
  Future<void> _deleteFolderRecursively(String folderId, String parentPath, String? driveFolderId) async {
    // Get the folder document reference
    final folderRef = _getDocumentReference(folderId, parentPath);

    // Get all items inside this folder
    final subItemsQuery = folderRef.collection('folders');
    final subItemsSnapshot = await subItemsQuery.get();

    // Delete all sub-items recursively
    for (final doc in subItemsSnapshot.docs) {
      final itemData = doc.data();
      final isSubFolder = itemData['isFolder'] ?? false;
      final subDriveFolderId = itemData['driveFolderId'];

      if (isSubFolder) {
        // Recursively delete sub-folders
        await _deleteFolderRecursively(doc.id, '$parentPath/$folderId/folders', subDriveFolderId);
      } else {
        // Delete files
        await _deleteSingleItem(doc.id, itemData, '$parentPath/$folderId/folders');
      }
    }

    // Finally delete the folder itself from Firebase
    await folderRef.delete();

    // Also delete the Google Drive folder if it exists
    if (driveFolderId != null && driveFolderId.isNotEmpty) {
      await _deleteFromGoogleDrive(driveFolderId);
    }
  }

  // GET DOCUMENT REFERENCE HELPER
  DocumentReference _getDocumentReference(String itemId, String parentPath) {
    final pathParts = parentPath.split('/');

    if (pathParts.length <= 3) {
      return FirebaseFirestore.instance
          .collection('folders')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('folders')
          .doc(itemId);
    } else {
      return FirebaseFirestore.instance
          .collection(pathParts[0])
          .doc(pathParts[1])
          .collection(pathParts[2])
          .doc(pathParts[3])
          .collection('folders')
          .doc(itemId);
    }
  }

  // DELETE FROM GOOGLE DRIVE
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
      // Don't show error to user if Drive deletion fails, as Firebase deletion already succeeded
    }
  }

  // RENAME FUNCTIONALITY - FIXED FOR FOLDERS
  Future<void> _renameItem(String itemId, Map<String, dynamic> itemData, String parentPath) async {
    final bool isFolder = itemData['isFolder'] ?? false;
    final String currentName = itemData['name'] ?? '';
    final String? driveId = itemData['driveId'];
    final String? driveFolderId = itemData['driveFolderId']; // For folders

    final TextEditingController nameController = TextEditingController(text: currentName);

    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${isFolder ? 'Folder' : 'File'}'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: "Enter new name",
            border: OutlineInputBorder(),
          ),
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
              } else {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentName) return;

    try {
      // Update in Firebase
      final docRef = _getDocumentReference(itemId, parentPath);
      await docRef.update({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // For files: rename in Google Drive
      if (!isFolder && driveId != null && driveId.isNotEmpty) {
        await _renameInGoogleDrive(driveId, newName);
      }
      // For folders: rename Google Drive folder if it exists
      else if (isFolder && driveFolderId != null && driveFolderId.isNotEmpty) {
        await _renameInGoogleDrive(driveFolderId, newName);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renamed to "$newName"')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error renaming: ${e.toString()}')),
      );
    }
  }

  // RENAME IN GOOGLE DRIVE
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
      // Don't show error to user if Drive rename fails, as Firebase rename already succeeded
    }
  }

  Future<void> _uploadToGoogleDrive(File image, String firebasePath) async {
    final fileName = await _showImageNameDialog();
    setState(() {
      _isUploadingToDrive = true;
      _driveUploadStatus = 'Preparing upload...';
    });

    try {
      // Sign in with personal Google account
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          _isUploadingToDrive = false;
          _driveUploadStatus = 'Sign-in cancelled';
        });
        return;
      }

      // Force token refresh to ensure we have latest credentials
      final googleAuth = await googleUser.authentication;
      final authHeaders = {
        'Authorization': 'Bearer ${googleAuth.accessToken}',
      };

      final authenticatedClient = GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticatedClient);

      setState(() {
        _driveUploadStatus = 'Creating folder structure...';
      });

      // Get or create root folder in user's personal Drive
      String? parentFolderId = await _getOrCreateAppRootFolder(driveApi);

      final mimeType = lookupMimeType(image.path) ?? 'application/octet-stream';

      setState(() {
        _driveUploadStatus = 'Uploading $fileName...';
      });

      final driveFile = drive.File();
      driveFile.name = fileName;
      if (parentFolderId != null) {
        driveFile.parents = [parentFolderId];
      }

      final media = drive.Media(
        image.openRead(),
        image.lengthSync(),
        contentType: mimeType,
      );

      // Upload the file to user's personal Drive
      final uploadedFile = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
      );

      // Set permissions to make the file viewable
      final permission = drive.Permission()
        ..type = 'anyone'
        ..role = 'reader';

      await driveApi.permissions.create(permission, uploadedFile.id!);

      // Generate direct links
      final webViewLink = 'https://drive.google.com/file/d/${uploadedFile.id}/view';
      final webViewLink2 = 'https://drive.google.com/uc?export=view&id=${uploadedFile.id}';
      final downloadLink = 'https://drive.google.com/uc?export=download&id=${uploadedFile.id}';

      // Store the links in Firebase
      await _storeDriveLinkInFirebase(
        webViewLink,
        webViewLink2,
        downloadLink,
        fileName!,
        firebasePath,
      );

      setState(() {
        _isUploadingToDrive = false;
        _driveUploadStatus = 'Upload complete!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File uploaded to your Google Drive')),
      );
    } catch (e) {
      setState(() {
        _isUploadingToDrive = false;
        _driveUploadStatus = 'Upload failed: ${e.toString()}';
      });
      print('Error uploading to Drive: $e');
    }
  }

  Future<void> _storeDriveLinkInFirebase(
      String webViewLink,
      String webViewLink2,
      String downloadLink,
      String fileName,
      String firebasePath,
      ) async
  {
    final user = FirebaseAuth.instance.currentUser!;
    final pathParts = firebasePath.split('/');

    DocumentReference docRef;
    if (pathParts.length <= 3) {
      docRef = FirebaseFirestore.instance
          .collection('folders')
          .doc(user.uid)
          .collection('folders')
          .doc('IMG_${DateTime.now().millisecondsSinceEpoch}');
    } else {
      docRef = FirebaseFirestore.instance
          .collection(pathParts[0])
          .doc(pathParts[1])
          .collection(pathParts[2])
          .doc(pathParts[3])
          .collection('folders')
          .doc('IMG_${DateTime.now().millisecondsSinceEpoch}');
    }

    await docRef.set({
      'name': fileName,
      'createdAt': FieldValue.serverTimestamp(),
      'isFolder': false,
      'webViewLink': webViewLink2,
      'downloadLink': downloadLink,
      'type': 'image',
      'driveId': webViewLink.split('/')[5], // Extract the Drive file ID
    });
  }

  Future<String?> _getOrCreateAppRootFolder(drive.DriveApi driveApi) async {
    const folderName = 'DocumentManagerUploads';
    try {
      // Check if folder exists in user's root Drive
      final response = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder' "
            "and name='$folderName' "
            "and 'root' in parents "
            "and trashed=false",
        spaces: 'drive',
      );

      if (response.files != null && response.files!.isNotEmpty) {
        return response.files!.first.id;
      }

      // Create new folder in user's root Drive
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = ['root']; // Important - creates in user's root Drive

      final createdFolder = await driveApi.files.create(folder);
      return createdFolder.id;
    } catch (e) {
      print('Error creating root folder: $e');
      return null;
    }
  }

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
        title: const Text('Root Folders'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _addRootFolder(context),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            onPressed: _addImage,
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder(
            stream: FirebaseFirestore.instance
                .collection('folders')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .collection('folders')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No folders found"));
              }

              final docs = snapshot.data!.docs;

              return GridView.builder(
                itemCount: docs.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  childAspectRatio: 0.75,
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final itemData = docs[index].data() as Map<String, dynamic>;
                  final itemId = docs[index].id;
                  final itemName = itemData['name'] ?? 'Unnamed';
                  final isFolder = itemData['isFolder'] ?? false;
                  final webViewLink = itemData['webViewLink'];
                  final parentPath = 'folders/${FirebaseAuth.instance.currentUser!.uid}/folders';

                  return FocusedMenuHolder(
                    menuWidth: 220,
                    blurSize: 0,
                    blurBackgroundColor: Colors.white,
                    onPressed: (){},
                    menuItems: [
                      FocusedMenuItem(
                        title: const Text("Delete"),
                        onPressed: () => _deleteItem(itemId, itemData, parentPath),
                        trailingIcon: const Icon(Icons.delete_outline),
                      ),
                      FocusedMenuItem(
                        title: const Text("Rename"),
                        onPressed: () => _renameItem(itemId, itemData, parentPath),
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
                                      parentPath: parentPath,
                                      folderId: itemId,
                                      folderName: itemName,
                                      driveFolderId: itemData['driveFolderId'],
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
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
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
                          itemName,
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

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}