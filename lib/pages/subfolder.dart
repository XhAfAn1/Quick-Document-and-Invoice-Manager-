import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'subfolder.dart'; // for deeper levels

class SubfolderPage extends StatelessWidget {
  final String parentPath;  // path like 'folders/docId/subfolders/docId/...'
  final String folderId;    // ID of the current folder
  final String folderName;  // Display name

  const SubfolderPage({
    super.key,
    required this.parentPath,
    required this.folderId,
    required this.folderName,
  });

  String get currentPath => '$parentPath/$folderId/subfolders';

  void _addSubfolder(BuildContext context, String currentPath) {
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
            onPressed: () => Navigator.of(context).pop(), // Cancel
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final folderName = folderNameController.text.trim();
              if (folderName.isEmpty) return;

              await FirebaseFirestore.instance
                  .collection(currentPath)
                  .doc(DateTime.now().millisecondsSinceEpoch.toString())
                  .set({
                'name': folderName,
                'createdAt': FieldValue.serverTimestamp(),
                'isFolder': true,
              });

              Navigator.of(context).pop(); // Close dialog
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }


  void _addImage() async {
    FirebaseFirestore.instance.collection(currentPath).doc('IMG ${DateTime.now().millisecondsSinceEpoch.toString()}').set({
      'name': 'Image',
      'createdAt': FieldValue.serverTimestamp(),
      'isFolder':false
    });
  }

  @override
  Widget build(BuildContext context) {
    final subfolderStream =
    FirebaseFirestore.instance.collection(currentPath).snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(folderName),
        backgroundColor: Colors.white,
        actions: [
          IconButton(icon: Icon(Icons.add), onPressed:(){ _addSubfolder(context,currentPath);}),
          IconButton(onPressed: _addImage, icon: Icon(Icons.add_a_photo_outlined)),
        ],
      ),
      body: StreamBuilder(
        stream: subfolderStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No subfolders found"));
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
              final data = docs[index].data() as Map<String, dynamic>;
              final subfolderId = docs[index].id;
              final subfolderName = data['name'] ?? 'Unnamed';

              return Column(
                children: [
                  SizedBox(
                    height: 100,
                    width: 100,
                    child: InkWell(
                      onTap: () {
                        data['isFolder'] ?
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SubfolderPage(
                              parentPath: currentPath,
                              folderId: subfolderId,
                              folderName: subfolderName,
                            ),
                          ),
                        ):();
                      },
                      child: data['isFolder']? Image.asset("assets/efolder.jpg"):Image.asset("assets/efile.png"),
                    ),
                  ),
                  Text(subfolderName,overflow: TextOverflow.ellipsis,
                    maxLines: 1,),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
