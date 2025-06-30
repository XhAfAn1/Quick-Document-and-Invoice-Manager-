import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:document_manager/pages/subfolder.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../authentication/signin.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  void _addRootFolder(BuildContext context) async {
    final TextEditingController folderNameController = TextEditingController();

    // Show dialog to enter folder name
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
            onPressed: () => Navigator.of(context).pop(), // Cancel
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final folderName = folderNameController.text.trim();
              if (folderName.isEmpty) return;

              final user = FirebaseAuth.instance.currentUser!;
              final userDoc = FirebaseFirestore.instance.collection("folders").doc(user.uid);

              // Create or update user doc
              await userDoc.set({
                'userName': user.displayName ?? 'User',
                'email': user.email ?? 'Email',
                'createdAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

              // Add folder with provided name
              await userDoc.collection('folders').doc(DateTime.now().millisecondsSinceEpoch.toString()).set({
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


  void _signOut() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => SignInPage()),
          (route) => false,
    );
  }

  void _addImage() async {
    final user = FirebaseAuth.instance.currentUser!;
    final userDoc = FirebaseFirestore.instance.collection("folders").doc(user.uid);


    // Create user document (if it doesn't already exist)
    await userDoc.set({
      'userName': user.displayName ?? 'User',
      'email': user.email ?? 'Email',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)); // avoids overwriting if exists

    // Create a root folder for the user inside their folders collection
    await userDoc.collection('folders').doc('IMG ${DateTime.now().millisecondsSinceEpoch.toString()}').set({
      'name': 'Image',
      'createdAt': FieldValue.serverTimestamp(),
      'isFolder':false
    });

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Root Folders'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(onPressed:(){ _addRootFolder(context);}, icon: Icon(Icons.add)),
          IconButton(onPressed: _addImage, icon: Icon(Icons.add_a_photo_outlined)),
          IconButton(onPressed: _signOut, icon: Icon(Icons.logout)),

        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('folders').doc(FirebaseAuth.instance.currentUser!.uid).collection('folders').snapshots(),
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
              final folderData = docs[index].data() as Map<String, dynamic>;
              final folderId = docs[index].id;
              final folderName = folderData['name'] ?? 'Unnamed';

              return Column(
                children: [
                  SizedBox(
                    height: 100,
                    width: 100,
                    child: InkWell(
                      onTap: () {
                        folderData['isFolder'] ?
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SubfolderPage(
                              parentPath: 'folders/${FirebaseAuth.instance.currentUser!.uid}/folders',
                              folderId: folderId,
                              folderName: folderName,
                            ),
                          ),
                        ):();
                      },
                      child: folderData['isFolder']? Image.asset("assets/efolder.jpg"):Image.asset("assets/efile.png"),
                    ),
                  ),
                  Text(folderName),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
