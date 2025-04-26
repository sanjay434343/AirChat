import 'package:http/http.dart' as http;
import 'dart:convert';

class TenorService {
  static const String apiKey = 'AIzaSyC_G7Tj1cGdaQTIgtJcfzG637YgdRDYzrU';
  static const String baseUrl = 'https://tenor.googleapis.com/v2';

  Future<List<GifItem>> searchGifs(String query, {int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/search?q=$query&key=$apiKey&limit=$limit&media_filter=minimal'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['results'] as List)
          .map((gif) => GifItem.fromJson(gif))
          .toList();
    }
    throw Exception('Failed to load GIFs');
  }

  Future<List<GifItem>> getTrendingGifs({int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/featured?key=$apiKey&limit=$limit&media_filter=minimal'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['results'] as List)
          .map((gif) => GifItem.fromJson(gif))
          .toList();
    }
    throw Exception('Failed to load trending GIFs');
  }

  Future<List<GifItem>> searchEmojis(String query, {int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/emoji?q=$query&key=$apiKey&limit=$limit'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['results'] as List)
          .map((emoji) => GifItem.fromJson(emoji))
          .toList();
    }
    throw Exception('Failed to load emojis');
  }

  Future<List<GifItem>> getTrendingEmojis({int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/featured_emoji?key=$apiKey&limit=$limit'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['results'] as List)
          .map((emoji) => GifItem.fromJson(emoji))
          .toList();
    }
    throw Exception('Failed to load trending emojis');
  }
}

class GifItem {
  final String id;
  final String url;
  final String previewUrl;

  GifItem({
    required this.id,
    required this.url,
    required this.previewUrl,
  });

  factory GifItem.fromJson(Map<String, dynamic> json) {
    final media = json['media_formats'];
    return GifItem(
      id: json['id'],
      url: media['gif']['url'],
      previewUrl: media['tinygif']['url'],
    );
  }
}
