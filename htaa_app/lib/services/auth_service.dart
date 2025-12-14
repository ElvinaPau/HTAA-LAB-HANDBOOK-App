import 'package:google_sign_in/google_sign_in.dart';
import 'package:htaa_app/services/bookmark_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import '../api_config.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
      'https://www.googleapis.com/auth/userinfo.profile',
    ],
    clientId:
        Platform.isIOS
            ? '892180593873-0in0o6tsk5ni5p3quuuptconl3cqjomr.apps.googleusercontent.com'
            : null,
  );

  GoogleSignInAccount? _currentUser;

  // Getters
  bool get isLoggedIn => _currentUser != null;
  String get userName => _currentUser?.displayName ?? 'User';
  String get userEmail => _currentUser?.email ?? '';
  String? get googleId => _currentUser?.id;
  String? get userPhotoUrl {
    if (_currentUser?.photoUrl != null) {
      final url = _currentUser!.photoUrl!;
      if (url.contains('googleusercontent.com')) {
        return url.contains('=s') ? url : '$url=s200-c';
      }
      return url;
    }
    return null;
  }

  // Initialize and check for existing session
  Future<void> initialize() async {
    try {
      // Try to sign in silently (restore previous session)
      _currentUser = await _googleSignIn.signInSilently();

      // Load from SharedPreferences if silent sign-in fails
      if (_currentUser == null) {
        final prefs = await SharedPreferences.getInstance();
        final userData = prefs.getString('user_data');
        if (userData != null) {
          // User data exists, try to restore session
          await _googleSignIn.signInSilently();
          _currentUser = _googleSignIn.currentUser;
        }
      } else {
        // Save user data
        await _saveUserData();
      }

      print('Initialize - Photo URL: ${_currentUser?.photoUrl}');
    } catch (error) {
      print('Error initializing auth: $error');
    }
  }

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      if (Platform.isIOS) {
        await Future.delayed(const Duration(milliseconds: 1000));
        await _googleSignIn.disconnect();
      }

      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account != null) {
        await Future.delayed(const Duration(milliseconds: 1000));

        _currentUser = account;
        await _saveUserData();

        // Debug: Print all account details
        print('Sign-in account details:');
        print('  displayName: ${account.displayName}');
        print('  email: ${account.email}');
        print('  id: ${account.id}');
        print('  photoUrl: ${account.photoUrl}');

        // Send user to backend API
        final url = '${getBaseUrl()}/api/users';
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'google_id': account.id,
            'name': account.displayName ?? '',
            'email': account.email,
            'photo_url': account.photoUrl ?? '',
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          print('User successfully stored in backend.');
        } else {
          print('Failed to save user to backend: ${response.body}');
        }

        // Sync local bookmarks to cloud after successful sign-in
        print('Syncing local bookmarks to cloud...');
        final bookmarkService = BookmarkService();
        await bookmarkService.syncPendingActions();
        print('Bookmark sync complete');

        return true;
      }
      return false;
    } catch (error) {
      print('Error signing in with Google: $error');
      print('Error details: ${error.runtimeType}');
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;

      // Clear saved data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');

      print('Successfully signed out');
    } catch (error) {
      print('Error signing out: $error');
    }
  }

  // Save user data to SharedPreferences
  Future<void> _saveUserData() async {
    if (_currentUser != null) {
      final prefs = await SharedPreferences.getInstance();
      final userData = json.encode({
        'displayName': _currentUser!.displayName,
        'email': _currentUser!.email,
        'photoUrl': _currentUser!.photoUrl,
        'id': _currentUser!.id,
      });
      await prefs.setString('user_data', userData);
    }
  }

  // Listen to auth state changes
  Stream<GoogleSignInAccount?> get onAuthStateChanged =>
      _googleSignIn.onCurrentUserChanged;
}
