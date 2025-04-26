import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

enum MessageType { text, image, gif, video, emoji }

class ChatMessage {
  final String id;
  final String content;
  final bool isMe;
  final DateTime timestamp;
  final MessageType type;
  final ChatMessage? replyTo; // Add reference to replied message

  ChatMessage({
    String? id,
    required this.content,
    required this.isMe,
    this.type = MessageType.text,
    DateTime? timestamp,
    this.replyTo,  // Add to constructor
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'type': type.index,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'replyTo': replyTo?.toJson(),  // Add reply serialization
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json, bool isMe) {
    return ChatMessage(
      id: json['id'],
      content: json['content'],
      type: MessageType.values[json['type']],
      isMe: isMe,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      replyTo: json['replyTo'] != null 
          ? ChatMessage.fromJson(json['replyTo'], isMe)
          : null,
    );
  }
}

class ChatService {
  static const int tcpPort = 42421; // Changed from TCP_PORT
  static const String messageDelimiter = "\n"; // Changed from MESSAGE_DELIMITER
  static const int chunkSize = 1024; // Changed from CHUNK_SIZE
  Socket? _socket;
  ServerSocket? _server;
  final StreamController<ChatMessage> _messageController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get messageStream => _messageController.stream;
  final StringBuffer _messageBuffer = StringBuffer();

  Future<void> startServer() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, tcpPort);
    _server!.listen((socket) {
      _handleConnection(socket);
    });
  }

  Future<void> connectToServer(String ip) async {
    _socket = await Socket.connect(ip, tcpPort);
    _handleConnection(_socket!);
  }

  void _handleConnection(Socket socket) {
    _socket = socket;
    socket.listen(
      (data) {
        try {
          // Add received data to buffer
          String receivedData = utf8.decode(data);
          _messageBuffer.write(receivedData);

          // Process complete messages
          _processBuffer();
        } catch (e) {
          print('Error handling data: $e');
        }
      },
      onError: (error) {
        print('Socket error: $error');
        _messageController.addError(error);
      },
      onDone: () {
        socket.destroy();
      },
    );
  }

  void _processBuffer() {
    try {
      String bufferedData = _messageBuffer.toString();
      List<String> messages = bufferedData.split(messageDelimiter);

      // Process complete messages
      for (int i = 0; i < messages.length - 1; i++) {
        if (messages[i].isNotEmpty) {
          try {
            Map<String, dynamic> messageData = jsonDecode(messages[i]);
            final message = ChatMessage.fromJson(messageData, false);
            _messageController.add(message);
          } catch (e) {
            print('Error parsing message: $e');
          }
        }
      }

      // Keep incomplete message in buffer
      _messageBuffer.clear();
      if (messages.isNotEmpty) {
        _messageBuffer.write(messages.last);
      }
    } catch (e) {
      print('Error processing buffer: $e');
    }
  }

  Future<void> sendMessage(
    String content, {
    MessageType type = MessageType.text,
    ChatMessage? replyTo,
  }) async {
    if (_socket != null) {
      try {
        final message = ChatMessage(
          content: content.trim(),
          isMe: true,
          type: type,
          replyTo: replyTo,
        );
        
        final messageData = jsonEncode(message.toJson()) + messageDelimiter;
        _socket!.add(utf8.encode(messageData));
        await _socket!.flush();
        _messageController.add(message);
      } catch (e) {
        _messageController.addError(e);
        rethrow;
      }
    }
  }

  Future<void> sendLargeFile(List<int> bytes, MessageType type, 
      {Function(double)? onProgress}) async {
    if (_socket == null) return;

    try {
      final String fileId = DateTime.now().millisecondsSinceEpoch.toString();
      final int totalChunks = (bytes.length / chunkSize).ceil();
      final Map<String, List<int>> receivedChunks = {};
      
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = min(start + chunkSize, bytes.length);
        final chunk = bytes.sublist(start, end);
        final base64Chunk = base64Encode(chunk);

        final chunkMessage = {
          'type': 'chunk',
          'fileId': fileId,
          'chunkIndex': i,
          'totalChunks': totalChunks,
          'data': base64Chunk,
          'messageType': type.index,
        };

        final messageData = jsonEncode(chunkMessage) + messageDelimiter;
        _socket!.add(utf8.encode(messageData));
        await _socket!.flush();

        if (onProgress != null) {
          onProgress((i + 1) / totalChunks);
        }

        // Small delay to prevent overwhelming the connection
        await Future.delayed(Duration(milliseconds: 10));
      }

    } catch (e) {
      print('Error sending large file: $e');
      rethrow;
    }
  }

  void dispose() {
    _socket?.destroy();
    _server?.close();
    _messageController.close();
  }
}
