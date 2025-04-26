import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'dart:convert';
import 'dart:async';
import '../models/device.dart';
import '../services/chat_service.dart';
import '../services/sound_service.dart';
import '../services/tenor_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';

class ChatScreen extends StatefulWidget {
  final Device peerDevice;
  final bool isServer;
  // NEW: add isSender field representing if the local user is sender
  final bool isSender;

  const ChatScreen({
    super.key,
    required this.peerDevice,
    this.isServer = false,
    required this.isSender, // caller must pass local ownership
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ImagePicker _imagePicker = ImagePicker();
  final _soundService = SoundService();
  bool _isConnected = false;
  bool _isConnecting = true;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 3;
  ChatMessage? _replyingTo;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    setState(() {
      _isConnecting = true;
      _isConnected = false;
    });

    try {
      if (widget.isServer) {
        await _chatService.startServer();
      } else {
        await _chatService.connectToServer(widget.peerDevice.ip);
      }

      _chatService.messageStream.listen(
        (message) {
          setState(() {
            final index = _messages.indexWhere((m) => m.id == message.id);
            if (index != -1) {
              _messages[index] = message; // update existing message
            } else {
              _messages.add(message);
            }
            _isConnected = true;
            _isConnecting = false;
            _resetReconnectAttempts();
          });
          _soundService.playMessageReceived();
        },
        onError: (error) {
          print('Connection error: $error');
          _handleConnectionError();
        },
        onDone: () {
          print('Connection closed');
          _handleConnectionError();
        },
      );

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });
      _resetReconnectAttempts();
    } catch (e) {
      print('Failed to initialize chat: $e');
      _handleConnectionError();
    }
  }

  void _handleConnectionError() {
    if (!mounted) return;
    
    setState(() {
      _isConnected = false;
      _isConnecting = false;
    });

    if (_reconnectAttempts < maxReconnectAttempts) {
      _scheduleReconnect();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection lost. Tap retry to reconnect.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _manualReconnect,
          ),
        ),
      );
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: 2), () {
      if (mounted && !_isConnected && !_isConnecting) {
        _reconnectAttempts++;
        _initializeChat();
      }
    });
  }

  void _manualReconnect() {
    _resetReconnectAttempts();
    _initializeChat();
  }

  void _resetReconnectAttempts() {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
  }

  Future<void> _sendMessage(String text) async {
    if (text.isNotEmpty) {
      try {
        await _chatService.sendMessage(
          text,
          type: MessageType.text,
          replyTo: _replyingTo,
        );
        _messageController.clear();
        setState(() => _replyingTo = null);
        await _soundService.playMessageSent();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error sending message: $e')),
          );
        }
      }
    }
  }

  Future<void> _sendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,  // Limit image size
        maxHeight: 1024,
        imageQuality: 70  // Compress image
      );
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Image = base64Encode(bytes);
        await _chatService.sendMessage(base64Image, type: MessageType.image);
        await _soundService.playMessageSent();  // Wait for sound to start
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending image: $e')),
        );
      }
    }
  }

  void _showEditMessageDialog(ChatMessage message) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Message'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'Enter new text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                // Update message locally; in a real app, also update on the server.
                final index = _messages.indexWhere((m) => m.id == message.id);
                if (index != -1) {
                  _messages[index] = ChatMessage(
                    id: message.id,
                    content: controller.text.trim(),
                    isMe: message.isMe,
                    type: MessageType.text,
                    timestamp: DateTime.now(),
                    replyTo: message.replyTo,
                  );
                }
              });
              Navigator.pop(context);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      reverse: true,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[_messages.length - 1 - index];
        return Dismissible(
          key: Key(message.id),
          // Shorter swipe animation durations
          resizeDuration: Duration(milliseconds: 300),
          movementDuration: Duration(milliseconds: 300),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (direction) async {
            setState(() => _replyingTo = message);
            return false;
          },
          child: _MessageBubble(
            message: message,
            peerName: widget.peerDevice.profile.name, // <-- pass peer name here
            isSender: widget.isSender, // NEW: pass the flag
            onDelete: () {
              setState(() {
                _messages.removeWhere((m) => m.id == message.id);
              });
            },
            onEdit: message.isMe
                ? () => _showEditMessageDialog(message)
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerDevice.profile.name),
            Text(
              _isConnecting 
                  ? 'Connecting...' 
                  : (_isConnected ? 'Connected' : 'Disconnected'),
              style: TextStyle(
                fontSize: 12,
                color: _isConnected 
                    ? Colors.green 
                    : (_isConnecting ? Colors.orange : Colors.red),
              ),
            ),
          ],
        ),
        actions: [
          if (!_isConnected && !_isConnecting)
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _initializeChat,
              tooltip: 'Retry connection',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/chat_bg.png',
              fit: BoxFit.cover,
            ),
          ),
          Column(
            children: [
              Expanded(child: _buildMessagesList()),
              if (_replyingTo != null)
                _ReplyPreview(
                  message: _replyingTo!,
                  receiverName: widget.peerDevice.profile.name,
                  onCancel: () => setState(() => _replyingTo = null),
                ),
              _MessageInput(
                controller: _messageController,
                onSend: () {
                  if (_messageController.text.isNotEmpty) {
                    _sendMessage(_messageController.text);
                  }
                },
                onImagePick: _sendImage,
                isConnected: _isConnected,
                chatService: _chatService,
                soundService: _soundService,
                replyingTo: _replyingTo,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _soundService.dispose();
    _chatService.dispose();
    _messageController.dispose();
    super.dispose();
  }
}

class _ReplyPreview extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onCancel;
  final String receiverName; // <-- new field

  const _ReplyPreview({
    required this.message,
    required this.onCancel,
    required this.receiverName, // <-- new param
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Color(0xFF617CFF).withAlpha(51), // 0.2 opacity
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFF617CFF),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Updated: if not sent by me, show receiverName instead of "They"
                Text(
                  message.isMe ? 'You' : receiverName,
                  style: TextStyle(
                    color: Color(0xFF617CFF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  message.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final String? peerName; // new parameter
  // NEW: local sender flag from ChatScreen
  final bool isSender;

  const _MessageBubble({
    required this.message,
    this.onDelete,
    this.onEdit,
    this.peerName,
    required this.isSender,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        // Show bottom sheet with options
        showModalBottomSheet(
          context: context,
          builder: (context) {
            return SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: Icon(Icons.delete),
                    title: Text('Delete'),
                    onTap: () {
                      Navigator.pop(context);
                      if (onDelete != null) onDelete!();
                    },
                  ),
                  if (onEdit != null)
                    ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Edit'),
                      onTap: () {
                        Navigator.pop(context);
                        onEdit!();
                      },
                    ),
                  ListTile(
                    leading: Icon(Icons.cancel),
                    title: Text('Cancel'),
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8), // Add more vertical spacing
        child: message.type == MessageType.image 
            ? _buildImageMessage(context)
            : _buildTextMessage(context),
      ),
    );
  }

  Widget _buildTextMessage(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        // Make bubble slightly longer by reducing the side margins
        left: message.isMe ? 48 : 8,
        right: message.isMe ? 8 : 48,
        top: 4,
        bottom: 4,
      ),
      child: Align(
        alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: message.isMe ? Color(0xFF352FED) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(message.isMe ? 20 : 4),
              topRight: Radius.circular(message.isMe ? 4 : 20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
            border: message.isMe 
                ? null 
                : Border.all(color: Color(0xFF617CFF).withAlpha(77)), // 0.3 opacity
          ),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: message.isMe 
                ? CrossAxisAlignment.end 
                : CrossAxisAlignment.start,
            children: [
              _buildMessageContent(context),
              SizedBox(height: 4),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: message.isMe 
                      ? Colors.white.withAlpha(179) // 0.7 opacity
                      : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageMessage(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                _buildMessageContent(context),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Widget _buildMessageContent(BuildContext context) {
    Widget messageContent;
    try {
      switch (message.type) {
        case MessageType.image:
          messageContent = GestureDetector(
            onTap: () => _showFullImage(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 250,
                  maxHeight: 350,
                ),
                child: Image.memory(
                  base64Decode(message.content),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('Error displaying image: $error');
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red),
                        Text(
                          'Image load failed',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
          break;
        case MessageType.gif:
          messageContent = Image.network(
            message.content,
            width: 200,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading GIF: $error');
              return Icon(Icons.error_outline, color: Colors.red);
            },
          );
          break;
        case MessageType.emoji:
          messageContent = Text(
            message.content,
            style: TextStyle(fontSize: 32),
          );
          break;
        case MessageType.video:
          messageContent = GestureDetector(
            onTap: () => _showFullVideo(context),
            child: Align(
              alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: 16),
                width: 250,
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoThumbnail(videoData: base64Decode(message.content)),
                      Container(color: Colors.black12),
                      Icon(Icons.play_circle_fill, size: 48, color: Colors.white),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatTime(message.timestamp),
                            style: TextStyle(fontSize: 10, color: Colors.white70),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          break;
        default:
          messageContent = Text(
            message.content,
            style: TextStyle(
              color: message.isMe ? Colors.white : Colors.black,
            ),
          );
      }
    } catch (e) {
      print('Error rendering message: $e');
      messageContent = Text(
        'Error displaying message',
        style: TextStyle(color: Colors.red),
      );
    }
    
    return Column(
      crossAxisAlignment: message.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (message.replyTo != null)
          _buildReplyPreview(context),
        messageContent,
      ],
    );
  }

  Widget _buildReplyPreview(BuildContext context) {
    // For local user:
    // If isSender==true, then my messages have isMe true.
    // If isSender==false (receiver), then local messages are marked with isMe false.
    final bool isReplyFromLocal = isSender ? message.replyTo!.isMe : !message.replyTo!.isMe;
    final senderLabel = isReplyFromLocal ? 'You' : (peerName ?? 'Unknown');
    
    return Container(
      margin: EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Color(0xFF617CFF).withAlpha(26), // 0.1 opacity
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Color(0xFF617CFF).withAlpha(51), // 0.2 opacity
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderLabel,
            style: TextStyle(
              color: Color(0xFF617CFF),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Text(
            message.replyTo!.content,
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: IconThemeData(color: Colors.white),
          ),
          body: PhotoView(
            imageProvider: MemoryImage(base64Decode(message.content)),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
          ),
        ),
      ),
    );
  }

  void _showFullVideo(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullScreenVideo(
          videoData: base64Decode(message.content),
        ),
      ),
    );
  }
}

class VideoThumbnail extends StatefulWidget {
  final Uint8List videoData;
  
  const VideoThumbnail({required this.videoData});
  
  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final file = await _createTempFile(widget.videoData);
      _controller = VideoPlayerController.file(file);
      await _controller.initialize();
      await _controller.setVolume(0.0);
      await _controller.seekTo(Duration.zero); // Seek to first frame
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      print('Error initializing video thumbnail: $e');
    }
  }

  Future<File> _createTempFile(Uint8List data) async {
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFile = File('${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.mp4');
    await tempFile.writeAsBytes(data);
    return tempFile;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        color: Colors.black54,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: VideoPlayer(_controller),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _FullScreenVideo extends StatefulWidget {
  final Uint8List videoData;

  const _FullScreenVideo({required this.videoData});

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.file(
        await _createTempFile(widget.videoData),
      );
      await _controller.initialize();
      if (mounted) setState(() => _isInitialized = true);
      _controller.play();
    } catch (e) {
      print('Error initializing video: $e');
    }
  }

  Future<File> _createTempFile(Uint8List data) async {
    final tempDir = await Directory.systemTemp.createTemp();
    final tempFile = File('${tempDir.path}/temp_video.mp4');
    await tempFile.writeAsBytes(data);
    return tempFile;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    IconButton(
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 64,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        });
                      },
                    ),
                  ],
                ),
              )
            : CircularProgressIndicator(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onImagePick;
  final bool isConnected;
  final ChatService chatService;
  final SoundService soundService;
  final ChatMessage? replyingTo;

  const _MessageInput({
    required this.controller,
    required this.onSend,
    required this.onImagePick,
    required this.isConnected,
    required this.chatService,
    required this.soundService,
    this.replyingTo,
  });

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> {
  Future<void> _showGifPicker(BuildContext context) async {
    final result = await showModalBottomSheet<GifItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GifPickerSheet(
        onGifSelected: (gif) async {
          Navigator.pop(context);
          await widget.chatService.sendMessage(gif.url, type: MessageType.gif);
          await widget.soundService.playMessageSent();
        },
        onEmojiSelected: (emoji) async {
          Navigator.pop(context);
          await widget.chatService.sendMessage(emoji, type: MessageType.text);
          await widget.soundService.playMessageSent();
        },
      ),
    );
  }

  Future<void> _sendPhotosOneByOne(List<XFile> photos) async {
    for (final photo in photos) {
      if (!mounted) return;
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(width: 16),
                Text('Sending photo ${photos.indexOf(photo) + 1}/${photos.length}...'),
              ],
            ),
            duration: Duration(seconds: 1),
          ),
        );
        
        final bytes = await photo.readAsBytes();
        final base64Image = base64Encode(bytes);
        await widget.chatService.sendMessage(
          base64Image, 
          type: MessageType.image,
        );
        await widget.soundService.playMessageSent();
        
        await Future.delayed(Duration(milliseconds: 500));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending photo: $e')),
        );
        break;
      }
    }
  }

  Future<void> _showAttachmentDialog(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.photo_library),
              ),
              title: Text('Photos'),
              subtitle: Text('Share multiple photos'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final List<XFile> photos = await ImagePicker().pickMultiImage(
                    imageQuality: 70,
                  );
                  
                  if (photos.isNotEmpty) {
                    await _sendPhotosOneByOne(photos);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error selecting photos: $e')),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.video_library),
              ),
              title: Text('Videos'),
              subtitle: Text('Share videos'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? video = await ImagePicker().pickVideo(
                  source: ImageSource.gallery,
                  maxDuration: Duration(minutes: 5),
                );
                
                if (video != null) {
                  await _handleVideoUpload(context, video);
                }
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.camera_alt),
              ),
              title: Text('Camera'),
              subtitle: Text('Take photo or video'),
              onTap: () async {
                Navigator.pop(context);
                _showCameraOptions(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCameraOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Media Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera),
              title: Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final XFile? image = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1024,
                    maxHeight: 1024,
                    imageQuality: 70,
                  );
                  if (image != null) {
                    final bytes = await image.readAsBytes();
                    final base64Image = base64Encode(bytes);
                    await widget.chatService.sendMessage(base64Image, type: MessageType.image);
                    await widget.soundService.playMessageSent();
                  }
                } catch (e) {
                  print('Error taking photo: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error taking photo: $e')),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.videocam),
              title: Text('Record Video'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? video = await ImagePicker().pickVideo(
                  source: ImageSource.camera,
                  maxDuration: Duration(minutes: 1),
                );
                if (video != null) {
                  await _handleVideoUpload(context, video);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleVideoUpload(BuildContext context, XFile video) async {
    try {
      final bytes = await video.readAsBytes();
      final fileSizeMB = bytes.length / (1024 * 1024);
      
      double progress = 0;
      // Show sending progress via SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(hours: 1),
          content: Row(
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(width: 16),
              Text('Sending video 0%'),
            ],
          ),
        ),
      );
      
      // Send the video in chunks with progress callback
      await widget.chatService.sendLargeFile(
        bytes,
        MessageType.video,
        onProgress: (p) {
          progress = p;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: Duration(hours: 1),
              content: Row(
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(width: 16),
                  Text('Sending video ${(progress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          );
        },
      );
      
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      // After sending chunks, send the final video message so the recipient shows a thumbnail
      await widget.chatService.sendMessage(
        base64Encode(bytes),
        type: MessageType.video,
      );
      
      await widget.soundService.playMessageSent();
    } catch (e) {
      print('Error sending video: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending video: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    
    return IgnorePointer(
      ignoring: !widget.isConnected,
      child: Container(
        padding: EdgeInsets.fromLTRB(8, 8, 8, bottomPadding + 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              offset: Offset(0, -1),
              blurRadius: 8,
              color: Colors.black.withOpacity(0.06),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Color(0xFF617CFF).withAlpha(26), // 0.1 opacity
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Color(0xFF617CFF),
                ),
              ),
              child: IconButton(
                icon: Icon(Icons.gif_box),
                onPressed: () => _showGifPicker(context),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withAlpha(26), // 0.1 opacity
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(77), // 0.3 opacity
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        CupertinoIcons.paperclip,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: () => _showAttachmentDialog(context),
                    ),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          border: InputBorder.none,
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF617CFF),
                    Color(0xFF352FED),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.send, color: Colors.white),
                onPressed: widget.onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GifPickerSheet extends StatefulWidget {
  final Function(GifItem) onGifSelected;
  final Function(String) onEmojiSelected;

  const _GifPickerSheet({
    required this.onGifSelected,
    required this.onEmojiSelected,
  });

  @override
  _GifPickerSheetState createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<_GifPickerSheet> 
    with SingleTickerProviderStateMixin {
  final _tenorService = TenorService();
  final _searchController = TextEditingController();
  late TabController _tabController;
  List<GifItem> _gifs = [];
  List<String> _recentEmojis = ['😀', '😍', '🎉', '👍', '🔥', '❤️', '😊', '🤔'];
  List<GifItem> _emojis = [];
  Timer? _debounce;
  bool _isLoading = false;
  bool _isLoadingEmojis = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTrendingGifs();
    _loadTrendingEmojis();
  }

  Future<void> _loadTrendingGifs() async {
    setState(() => _isLoading = true);
    try {
      final results = await _tenorService.getTrendingGifs();
      if (mounted) setState(() => _gifs = results);
    } catch (e) {
      print('Error loading trending GIFs: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTrendingEmojis() async {
    setState(() => _isLoadingEmojis = true);
    try {
      final results = await _tenorService.getTrendingEmojis();
      if (mounted) setState(() => _emojis = results);
    } catch (e) {
      print('Error loading emojis: $e');
    } finally {
      if (mounted) setState(() => _isLoadingEmojis = false);
    }
  }

  Future<void> _searchGifs(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isLoading = true);
      try {
        final results = await _tenorService.searchGifs(query);
        if (mounted) setState(() => _gifs = results);
      } catch (e) {
        print('Error searching GIFs: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  Future<void> _searchEmojis(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isLoadingEmojis = true);
      try {
        final results = await _tenorService.searchEmojis(query);
        if (mounted) setState(() => _emojis = results);
      } catch (e) {
        print('Error searching emojis: $e');
      } finally {
        if (mounted) setState(() => _isLoadingEmojis = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: 'GIFs'),
                    Tab(text: 'Emojis'),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onChanged: (query) {
                      if (_tabController.index == 0) {
                        _searchGifs(query);
                      } else {
                        _searchEmojis(query);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGifsGrid(),
                _buildEmojiGrid(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGifsGrid() {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : GridView.builder(
            padding: EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _gifs.length,
            itemBuilder: (context, index) {
              final gif = _gifs[index];
              return InkWell(
                onTap: () => widget.onGifSelected(gif),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    gif.previewUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded / 
                                progress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
  }

  Widget _buildEmojiGrid() {
    return _isLoadingEmojis
        ? Center(child: CircularProgressIndicator())
        : GridView.builder(
            padding: EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1,
            ),
            itemCount: _emojis.length,
            itemBuilder: (context, index) {
              final emoji = _emojis[index];
              return InkWell(
                onTap: () => widget.onEmojiSelected(emoji.url),
                child: Image.network(
                  emoji.previewUrl,
                  fit: BoxFit.contain,
                ),
              );
            },
          );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }
}
