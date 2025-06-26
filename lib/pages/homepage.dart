import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../authentication/signin.dart';

class homepage extends StatefulWidget {
  const homepage({super.key});

  @override
  State<homepage> createState() => _homepageState();
}

class _homepageState extends State<homepage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        actions: [
          IconButton(onPressed: (){
            FirebaseFirestore.instance
                .collection("folders")
                .doc(DateTime.now().toIso8601String())
                .set({'name': 'hello'});
          }, icon: Icon(Icons.add)),
          IconButton(onPressed: () async{
           await FirebaseAuth.instance.signOut();
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => SignInPage(),), (route) => false);
          }, icon: Icon(Icons.logout)),

        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('folders').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No folders found"));
          }

          final docs = snapshot.data!.docs;

          return GridView.builder(
            itemCount: docs.length,gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            childAspectRatio: 0.75,
           // mainAxisExtent: 400,
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,

          ),
            itemBuilder: (context, index) {
              final folderData = docs[index].data() as Map<String, dynamic>;
              final folderName = folderData['name'] ?? 'Unnamed';

              return Column(
                children: [
                Container(
                  height: 100,
                  width: 100,
                color: Colors.red,

              ),
                  Text(folderName),
                ],
              );
            },
          );
        },
      )

    );
  }
}
