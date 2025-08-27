// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'strapi_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StrapiFile _$StrapiFileFromJson(Map<String, dynamic> json) => StrapiFile(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      alternativeText: json['alternativeText'] as String?,
      caption: json['caption'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      formats: json['formats'] as Map<String, dynamic>?,
      hash: json['hash'] as String,
      ext: json['ext'] as String,
      mime: json['mime'] as String,
      size: (json['size'] as num).toDouble(),
      url: json['url'] as String,
      previewUrl: json['previewUrl'] as String?,
      provider: json['provider'] as String,
      providerMetadata: json['provider_metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$StrapiFileToJson(StrapiFile instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'alternativeText': instance.alternativeText,
      'caption': instance.caption,
      'width': instance.width,
      'height': instance.height,
      'formats': instance.formats,
      'hash': instance.hash,
      'ext': instance.ext,
      'mime': instance.mime,
      'size': instance.size,
      'url': instance.url,
      'previewUrl': instance.previewUrl,
      'provider': instance.provider,
      'provider_metadata': instance.providerMetadata,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
