// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FileModelAdapter extends TypeAdapter<FileModel> {
  @override
  final int typeId = 0;

  @override
  FileModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FileModel(
      id: fields[0] as String,
      name: fields[1] as String,
      url: fields[2] as String,
      fileName: fields[3] as String,
      fileType: fields[4] as String,
      faculty: fields[5] as String,
      level: fields[6] as String,
      field: fields[7] as String,
      unit: fields[8] as String,
      type: fields[9] as String,
      uploadedAt: fields[11] as DateTime,
      uploadedBy: fields[12] as String,
      favorites: (fields[13] as List).cast<String>(),
      downloadCount: fields[15] as int,
      viewCount: fields[16] as int,
      readingProgress: (fields[17] as Map).cast<String, double>(),
      lastOpened: fields[18] as DateTime?,
      localPath: fields[19] as String?,
      size: fields[10] as int?,
      viewedBy: (fields[14] as List).cast<String>(),
      storagePath: fields[20] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FileModel obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.fileName)
      ..writeByte(4)
      ..write(obj.fileType)
      ..writeByte(5)
      ..write(obj.faculty)
      ..writeByte(6)
      ..write(obj.level)
      ..writeByte(7)
      ..write(obj.field)
      ..writeByte(8)
      ..write(obj.unit)
      ..writeByte(9)
      ..write(obj.type)
      ..writeByte(10)
      ..write(obj.size)
      ..writeByte(11)
      ..write(obj.uploadedAt)
      ..writeByte(12)
      ..write(obj.uploadedBy)
      ..writeByte(13)
      ..write(obj.favorites)
      ..writeByte(14)
      ..write(obj.viewedBy)
      ..writeByte(15)
      ..write(obj.downloadCount)
      ..writeByte(16)
      ..write(obj.viewCount)
      ..writeByte(17)
      ..write(obj.readingProgress)
      ..writeByte(18)
      ..write(obj.lastOpened)
      ..writeByte(19)
      ..write(obj.localPath)
      ..writeByte(20)
      ..write(obj.storagePath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
