class AddressbookEntry {
  final String username;
  final String address;
  final bool isFavorite;
  final DateTime? addedAt;

  AddressbookEntry({
    required this.username,
    required this.address,
    this.isFavorite = false,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  // Create from JSON
  factory AddressbookEntry.fromJson(Map<String, dynamic> json) {
    return AddressbookEntry(
      username: json['username'] as String,
      address: json['address'] as String,
      isFavorite: json['isFavorite'] as bool? ?? false,
      addedAt: json['addedAt'] != null
          ? DateTime.parse(json['addedAt'] as String)
          : DateTime.now(),
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'address': address,
      'isFavorite': isFavorite,
      'addedAt': addedAt?.toIso8601String(),
    };
  }

  // Create a copy with modified fields
  AddressbookEntry copyWith({
    String? username,
    String? address,
    bool? isFavorite,
    DateTime? addedAt,
  }) {
    return AddressbookEntry(
      username: username ?? this.username,
      address: address ?? this.address,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AddressbookEntry &&
        other.username == username &&
        other.address == address;
  }

  @override
  int get hashCode => username.hashCode ^ address.hashCode;

  @override
  String toString() {
    return 'AddressbookEntry(username: $username, address: ${address.substring(0, 10)}..., isFavorite: $isFavorite)';
  }
}
