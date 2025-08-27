import 'package:json_annotation/json_annotation.dart';

part 'strapi_file.g.dart';

/// Represents a file uploaded to Strapi.
@JsonSerializable()
class StrapiFile {
  /// Creates a new [StrapiFile] instance.
  const StrapiFile({
    required this.id,
    required this.name,
    required this.alternativeText,
    required this.caption,
    required this.width,
    required this.height,
    required this.formats,
    required this.hash,
    required this.ext,
    required this.mime,
    required this.size,
    required this.url,
    required this.previewUrl,
    required this.provider,
    required this.providerMetadata,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a [StrapiFile] from a JSON map.
  factory StrapiFile.fromJson(Map<String, dynamic> json) =>
      _$StrapiFileFromJson(json);

  /// The unique identifier for the file.
  final int id;

  /// The original name of the file.
  final String name;

  /// Alternative text for accessibility.
  @JsonKey(name: 'alternativeText')
  final String? alternativeText;

  /// Caption for the file.
  final String? caption;

  /// Width of the image (null for non-images).
  final int? width;

  /// Height of the image (null for non-images).
  final int? height;

  /// Different format sizes for images.
  final Map<String, dynamic>? formats;

  /// Unique hash of the file.
  final String hash;

  /// File extension.
  final String ext;

  /// MIME type of the file.
  final String mime;

  /// Size of the file in bytes.
  final double size;

  /// Public URL to access the file.
  final String url;

  /// Preview URL for the file.
  @JsonKey(name: 'previewUrl')
  final String? previewUrl;

  /// Storage provider used.
  final String provider;

  /// Provider-specific metadata.
  @JsonKey(name: 'provider_metadata')
  final Map<String, dynamic>? providerMetadata;

  /// When the file was uploaded.
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// When the file was last updated.
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// Converts the file to a JSON map.
  Map<String, dynamic> toJson() => _$StrapiFileToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StrapiFile && other.id == id && other.hash == hash;
  }

  @override
  int get hashCode => Object.hash(id, hash);

  @override
  String toString() {
    return 'StrapiFile(id: $id, name: $name, url: $url)';
  }
}
