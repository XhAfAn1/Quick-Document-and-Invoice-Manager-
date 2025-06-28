import 'package:document_manager/pages/homepage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';


class SignInPage extends StatefulWidget {
  @override
  _SignInPageState createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();


  Future<void> _signIn(BuildContext context) async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    try {
      // Show loading indicator (optional)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Sign in with Firebase
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      // Close loading indicator
      Navigator.of(context).pop();

      Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => HomePage(),));

    } on FirebaseAuthException catch (e) {
      Navigator.of(context).pop(); // Close loading indicator if open

      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found for this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'invalid-email':
          message = 'Invalid email address.';
          break;
        default:
          message = 'Login failed. ${e.message}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong.')),
      );
      print('Error: $e');
    }
  }

  Future<void> _signInwithGoogle(BuildContext context) async {

  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign In')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Email field
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),

            // Password field
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 24),

            // Sign In Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (){
                  _signIn(context);
                },
                child: Text('Sign In'),
              ),
            ),
            SizedBox(height: 24),

            // Sign In Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (){
                  _signInwithGoogle(context);
                },
                icon: Icon(Icons.email),
                label: Text('Sign In with Google'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}