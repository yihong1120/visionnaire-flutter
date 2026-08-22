part of 'chat_page.dart';

mixin _ChatPageAttachments on _ChatPageStateBase {
  @override
  void _handleFileTap(Map<String, dynamic> attachment) async {
    final url = (attachment['url'] as String?).toString();
    if (url.isEmpty || url == "null") return;
    try {
      final resolved = await _resolveAttachmentUri(url);
      // We want to force download so maybe append download=true
      final dlUri = resolved.replace(
          queryParameters: {...resolved.queryParameters, 'download': 'true'});
      await _downloadWithAuth(dlUri);
    } catch (e) {
      debugPrint('Download error: $e');
    }
  }

  Future<Uri> _resolveAttachmentUri(String url) async {
    final baseUri = Uri.parse(await ChatAPIService.baseUrl);
    return AuthenticatedUri.resolvePathRelativeToBase(url, baseUri);
  }

  @override
  Future<Uint8List> _getAttachmentBytes(String url) async {
    final uri = await _resolveAttachmentUri(url);
    final key = uri.toString();
    if (_attachmentImageCache.containsKey(key)) {
      return _attachmentImageCache[key]!;
    }

    if (!mounted) throw Exception('Widget not mounted');
    return await AuthUtils.withAuthRetry(context, (token) async {
      final resp = await AuthenticatedHttp.get(
        uri,
        headers: AuthRequestHeaders.forRequest(token),
        timeout: const Duration(seconds: 30),
      );
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      return _attachmentImageCache[key] = resp.bodyBytes;
    });
  }

  @override
  Future<void> _pickImages({bool forEditing = false}) async {
    if (kIsWeb) {
      await _pickImagesFromGallery(forEditing: forEditing);
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromCamera(forEditing: forEditing);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('選擇相簿'),
              onTap: () {
                Navigator.pop(context);
                _pickImagesFromGallery(forEditing: forEditing);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> _uploadPickedFiles(List<LocalAttachmentBytes> files,
      {bool forEditing = false}) async {
    if (files.isEmpty) return;

    try {
      setState(() => _isBusy = true);

      // If we don't have a chat ID yet, create a new room immediately
      if (_actualChatId == null) {
        final room = await AuthUtils.withAuthRetry(
          context,
          (token) => _api.createRoom(token),
          notLoggedInMessage:
              AppLocalizations.of(context)!.notLoggedInOrInvalidToken,
        );
        _actualChatId = room['id'] as int;

        // Notify parent that a room was implicitly created
        if (mounted && widget.onMessageSent != null) {
          widget.onMessageSent!.call(
              _actualChatId, room['title'] as String? ?? 'New Chat',
              pendingQuestion: null);
        }
      }

      if (!mounted) return;
      final drafts = await AuthUtils.withAuthRetry(
        context,
        (token) => _api.uploadAttachments(token, _actualChatId!, files),
        notLoggedInMessage:
            AppLocalizations.of(context)!.notLoggedInOrInvalidToken,
      );

      if (!mounted) return;
      setState(() {
        if (forEditing) {
          // For editing, we might need a different handling or just add to editing attachments
          for (final d in drafts) {
            _editingAttachments.add(ChatEditingAttachment.fromServer({
              'id': d.id,
              'uuid': d.id.toString(), // compat
              'url': d.url,
              'preview_url': d.previewUrl,
              'original_name': d.originalName,
              'content_type': d.contentType,
            }));
          }
        } else {
          _draftAttachments.addAll(drafts);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          AppLocalizations.of(context)!.attachmentUploadFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  Future<void> _pickFiles({bool forEditing = false}) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    const maxBytes = 50 * 1024 * 1024; // 50 MB per file
    final localFiles = <LocalAttachmentBytes>[];

    for (final pf in result.files) {
      final bytes = pf.bytes;
      if (bytes == null) continue;
      if (bytes.length > maxBytes) {
        setState(() => _error = '檔案 ${pf.name} 超過 50MB 限制');
        continue;
      }
      final mime =
          _mimeFromExtension(pf.extension) ?? 'application/octet-stream';
      localFiles
          .add(LocalAttachmentBytes(name: pf.name, bytes: bytes, mime: mime));
    }

    await _uploadPickedFiles(localFiles, forEditing: forEditing);
  }

  String? _mimeFromExtension(String? ext) {
    if (ext == null) return null;
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
      'csv': 'text/csv',
    };
    return map[ext.toLowerCase()];
  }

  Future<void> _pickImageFromCamera({bool forEditing = false}) async {
    final imagePicker = ImagePicker();
    try {
      final pickedFile =
          await imagePicker.pickImage(source: ImageSource.camera);
      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      const maxBytes = 8 * 1024 * 1024;

      if (bytes.length > maxBytes) {
        setState(() => _error = '圖片 ${pickedFile.name} 超過 8MB 限制');
        return;
      }

      final localFile = LocalAttachmentBytes(
        name: pickedFile.name,
        bytes: bytes,
        mime: inferImageMime(pickedFile.name),
      );

      await _uploadPickedFiles([localFile], forEditing: forEditing);
    } catch (e) {
      setState(() => _error = '拍照時出錯: $e');
    }
  }

  Future<void> _pickImagesFromGallery({bool forEditing = false}) async {
    final imagePicker = ImagePicker();
    try {
      final pickedFiles = await imagePicker.pickMultiImage();
      if (pickedFiles.isEmpty) return;

      const maxBytes = 8 * 1024 * 1024;

      for (final pickedFile in pickedFiles) {
        final bytes = await pickedFile.readAsBytes();
        if (bytes.length > maxBytes) {
          setState(() => _error = '圖片 ${pickedFile.name} 超過 8MB 限制');
          continue;
        }
        await _uploadPickedFiles(
          [
            LocalAttachmentBytes(
              name: pickedFile.name,
              bytes: bytes,
              mime: inferImageMime(pickedFile.name),
            ),
          ],
          forEditing: forEditing,
        );
        if (!mounted) return;
      }
    } catch (e) {
      setState(() => _error = '選擇圖片時出錯: $e');
    }
  }

  String _inferFilename(Uri uri, Map<String, String> headers) {
    final cd = headers['content-disposition'] ?? headers['Content-Disposition'];
    if (cd != null) {
      final rfc5987 = RegExp(r"filename\*=([^']*)''([^;]+)");
      final m1 = rfc5987.firstMatch(cd);
      if (m1 != null) {
        try {
          final nameEnc = m1.group(2);
          if (nameEnc != null) return Uri.decodeComponent(nameEnc);
        } catch (_) {}
      }
      final simple = RegExp(r'filename\s*=\s*"?([^";]+)"?');
      final m2 = simple.firstMatch(cd);
      if (m2 != null && m2.groupCount >= 1) return m2.group(1)!;
    }
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'download.bin';
  }

  Future<void> _saveBytesMobile(
    String filename,
    List<int> bytes, {
    String? mimeType,
  }) async {
    final path = await saveBytesToTempFile(filename, bytes, mimeType: mimeType);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已儲存到暫存目錄: $path')),
      );
    }
  }

  @override
  Future<void> _downloadWithAuth(Uri uri) async {
    final local = AppLocalizations.of(context)!;
    setState(() => _isBusy = true);
    try {
      final trustedUri = AuthenticatedUri.resolve(
        uri,
        Uri.parse(await ChatAPIService.baseUrl),
      );
      if (!mounted) return;
      final resp = await AuthUtils.withAuthRetry(
        context,
        (token) => AuthenticatedHttp.get(
          trustedUri,
          headers: AuthRequestHeaders.forRequest(token),
          timeout: const Duration(seconds: ChatAPIService.timeoutSeconds),
        ),
        notLoggedInMessage: local.notLoggedIn,
      );

      if (resp.statusCode != 200) {
        throw Exception('Download failed (${resp.statusCode})');
      }
      final filename = _inferFilename(trustedUri, resp.headers);
      if (kIsWeb) {
        final mime = resp.headers['content-type'] ?? 'application/octet-stream';
        if (mime.startsWith('image/')) {
          cp.CrossPlatformDownload.downloadImage(resp.bodyBytes, filename);
        } else {
          final b64 = base64Encode(resp.bodyBytes);
          final dataUrl = Uri.parse('data:$mime;base64,$b64');
          await launchUrl(dataUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        final mime = resp.headers['content-type'];
        await _saveBytesMobile(filename, resp.bodyBytes, mimeType: mime);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Download error: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
