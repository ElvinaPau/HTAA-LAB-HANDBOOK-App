import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// A widget that intelligently displays images from either local cache or network
class CachedImageWidget extends StatelessWidget {
  final String imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedImageWidget({
    Key? key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Check if it's a cached image path
    if (imagePath.contains('cached_images')) {
      return _buildCachedImage();
    }

    // Check if it's a local file path (starts with '/')
    if (imagePath.startsWith('/')) {
      return _buildLocalImage();
    }

    // Otherwise, it's a network URL
    return _buildNetworkImage();
  }

  Widget _buildCachedImage() {
    return FutureBuilder<File?>(
      future: _getCachedImageFile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildPlaceholder();
        }

        if (snapshot.hasData && snapshot.data != null) {
          final file = snapshot.data!;
          return Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading cached image: $error');
              print('File path: ${file.path}');
              return _buildError();
            },
          );
        }

        // File doesn't exist
        print('Cached image file not found: $imagePath');
        return _buildError();
      },
    );
  }

  Future<File?> _getCachedImageFile() async {
    try {
      // Extract the filename from the path
      final filename = imagePath.split('/').last;

      // Get the app's document directory
      final appDir = await getApplicationDocumentsDirectory();

      // Construct the full path to the cached image
      final cachedImagePath = '${appDir.path}/cached_images/$filename';

      print('Looking for cached image at: $cachedImagePath');

      final file = File(cachedImagePath);

      if (await file.exists()) {
        print('Cached image found!');
        return file;
      } else {
        print('Cached image does not exist at path');
        return null;
      }
    } catch (e) {
      print('Error getting cached image file: $e');
      return null;
    }
  }

  Widget _buildLocalImage() {
    final file = File(imagePath);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildPlaceholder();
        }

        if (snapshot.hasData && snapshot.data == true) {
          return Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading local image: $error');
              return _buildError();
            },
          );
        }

        // File doesn't exist
        return _buildError();
      },
    );
  }

  Widget _buildNetworkImage() {
    return Image.network(
      imagePath,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) {
        print('Error loading network image: $error');
        return _buildError();
      },
    );
  }

  Widget _buildPlaceholder() {
    return placeholder ??
        Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Center(child: CircularProgressIndicator()),
        );
  }

  Widget _buildError() {
    return errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
        );
  }
}
