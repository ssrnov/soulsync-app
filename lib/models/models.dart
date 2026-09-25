class User {
  final String id;
  final String username;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final bool isPaired;
  final String? coupleId;
  final String? inviteCode;
  final String? currentMood;
  final String? quickNote;
  final bool isOnline;
  final String? phone;
  final String? bio;
  final String? birthday;
  final String? relationshipSince;
  final bool isPremium;
  final bool verified;
  final String? gender;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    required this.isPaired,
    this.coupleId,
    this.inviteCode,
    this.currentMood,
    this.quickNote,
    required this.isOnline,
    this.phone,
    this.bio,
    this.birthday,
    this.relationshipSince,
    this.isPremium = false,
    this.verified = false,
    this.gender,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    String? avatar;
    if (json['avatar'] != null) {
      if (json['avatar'] is String) {
        avatar = json['avatar'];
      } else if (json['avatar'] is Map) {
        avatar = json['avatar']['url'];
      }
    }
    return User(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      displayName: (json['displayName'] ?? json['username'] ?? '').toString(),
      avatarUrl: avatar,
      isPaired: _parseBool(json['isPaired']),
      coupleId: json['coupleId']?.toString(),
      inviteCode: json['inviteCode']?.toString(),
      currentMood: json['currentMood']?.toString(),
      quickNote: json['quickNote']?.toString(),
      isOnline: _parseBool(json['isOnline']),
      phone: json['phone']?.toString(),
      bio: json['bio']?.toString(),
      birthday: json['birthday']?.toString(),
      relationshipSince: json['relationshipSince']?.toString(),
      isPremium: _parseBool(json['isPremium']),
      verified: _parseBool(json['verified']),
      gender: json['gender']?.toString(),
    );
  }

  /// Safely parse boolean from various PHP/MySQL representations
  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'displayName': displayName,
    'avatar': avatarUrl,
    'isPaired': isPaired,
    'coupleId': coupleId,
    'inviteCode': inviteCode,
    'currentMood': currentMood,
    'quickNote': quickNote,
    'isOnline': isOnline,
  };
}

class Message {
  final String id;
  final String senderId;
  final String content;
  final String type;
  final String status;
  final DateTime createdAt;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderId;
  final bool viewOnce;
  final bool viewed;
  final String? caption;
  final String? pinnedAt;
  final List<Map<String, String>> reactions;

  Message({
    required this.id,
    required this.senderId,
    required this.content,
    required this.type,
    required this.status,
    required this.createdAt,
    this.replyToId,
    this.replyToText,
    this.replyToSenderId,
    this.viewOnce = false,
    this.viewed = false,
    this.caption,
    this.pinnedAt,
    this.reactions = const [],
  });

  static bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

  factory Message.fromJson(Map<String, dynamic> json) {
    List<Map<String, String>> rx = [];
    if (json['reactions'] is List) {
      for (final r in json['reactions']) {
        if (r is Map) rx.add({'userId': r['userId']?.toString() ?? '', 'emoji': r['emoji']?.toString() ?? ''});
      }
    }
    return Message(
      id: json['id'] ?? json['_id'] ?? '',
      senderId: json['senderId'] ?? json['sender'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
      status: json['status'] ?? 'sent',
      createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : DateTime.now(),
      replyToId: json['replyToId']?.toString(),
      replyToText: json['replyToText']?.toString(),
      replyToSenderId: json['replyToSenderId']?.toString(),
      viewOnce: _b(json['viewOnce']),
      viewed: _b(json['viewed']),
      caption: json['caption']?.toString(),
      pinnedAt: json['pinnedAt']?.toString(),
      reactions: rx,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'content': content,
    'type': type,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
  };
}

class Memory {
  final String id;
  final String title;
  final String? description;
  final String mediaUrl;
  final String mediaType;
  final DateTime memoryDate;

  Memory({
    required this.id,
    required this.title,
    this.description,
    required this.mediaUrl,
    required this.mediaType,
    required this.memoryDate,
  });

  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'] ?? json['_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      mediaUrl: json['mediaUrl'] ?? '',
      mediaType: json['mediaType'] ?? 'image',
      memoryDate: json['memoryDate'] != null 
        ? DateTime.parse(json['memoryDate']) 
        : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'mediaUrl': mediaUrl,
    'mediaType': mediaType,
    'memoryDate': memoryDate.toIso8601String(),
  };
}

class Mood {
  final String id;
  final String userId;
  final String mood;
  final DateTime createdAt;

  Mood({
    required this.id,
    required this.userId,
    required this.mood,
    required this.createdAt,
  });

  factory Mood.fromJson(Map<String, dynamic> json) {
    return Mood(
      id: json['id'] ?? json['_id'] ?? '',
      userId: json['userId'] ?? '',
      mood: json['mood'] ?? '',
      createdAt: json['createdAt'] != null 
        ? DateTime.parse(json['createdAt']) 
        : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'mood': mood,
    'createdAt': createdAt.toIso8601String(),
  };
}

class Game {
  final String id;
  final String type;
  final String status;
  final String? winnerId;

  Game({
    required this.id,
    required this.type,
    required this.status,
    this.winnerId,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'] ?? json['_id'] ?? '',
      type: json['type'] ?? '',
      status: json['status'] ?? 'pending',
      winnerId: json['winnerId'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'status': status,
    'winnerId': winnerId,
  };
}

class UsageStats {
  final String appName;
  final int durationSeconds;

  UsageStats({
    required this.appName,
    required this.durationSeconds,
  });

  factory UsageStats.fromJson(Map<String, dynamic> json) {
    return UsageStats(
      appName: json['appName'] ?? '',
      durationSeconds: json['durationSeconds'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'appName': appName,
    'durationSeconds': durationSeconds,
  };
}
