import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:document_manager/pages/homepage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'authentication/signin.dart';

class Wrapper extends StatefulWidget {
  const Wrapper({super.key});

  @override
  State<Wrapper> createState() => _WrapperState();
}

class _WrapperState extends State<Wrapper> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, userSnapshot) {
        // Step 1: Waiting for Firebase Auth to initialize
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
           // body: Center(child: CircularProgressIndicator()),
          );
        }

        // Step 2: If user is logged in
        else if (userSnapshot.hasData && userSnapshot.data != null) {
          final userId = userSnapshot.data!.uid;

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection("Users")
                .doc(userId)
                .get(),
            builder: (context, snapshot) {
              // Waiting for Firestore user document
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // Error while fetching document
              if (snapshot.hasError) {
                print("Error: ${snapshot.error}");
                return Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(
                    child: Text("Error: ${snapshot.error}"),
                  ),
                );
              }

              // Document not found or empty
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("User document does not exist."),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () =>
                              FirebaseAuth.instance.signOut(),
                          child: const Text("Sign Out"),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Document exists, parse it
              final userData =
              snapshot.data!.data() as Map<String, dynamic>;

              // You can pass `userData` to homepage() if needed
              return const HomePage();
            },
          );
        }

        // Step 3: If user is not logged in
        return SignInPage();
      },
    );
  }
}
