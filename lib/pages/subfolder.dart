import 'package:cloud_firestore/cloud_firestore.dart';
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

  void _addSubfolder() {
    FirebaseFirestore.instance.collection(currentPath).add({
      'name': 'New Subfolder',
      'createdAt': FieldValue.serverTimestamp(),
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
          IconButton(icon: Icon(Icons.add), onPressed: _addSubfolder),
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SubfolderPage(
                              parentPath: currentPath,
                              folderId: subfolderId,
                              folderName: subfolderName,
                            ),
                          ),
                        );
                      },
                      child: Image.asset("assets/efolder.jpg"),
                    ),
                  ),
                  Text(subfolderName),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
