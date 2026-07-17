class AddressbookEntry {
  final String label;
  final String address;
  final DateTime createdAt;

  const AddressbookEntry({
    required this.label,
    required this.address,
    required this.createdAt,
  });

  factory AddressbookEntry.fromJson(Map<String, dynamic> json) {
    final rawLabel = (json['label'] ?? json['username'] ?? '').toString().trim();
    final rawAddress = (json['address'] ?? '').toString().trim();
    final rawAddedAt = json['addedAt']?.toString();

    return AddressbookEntry(
      label: rawLabel,
      address: rawAddress,
      createdAt: DateTime.tryParse(rawAddedAt ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'address': address,
      'addedAt': createdAt.toIso8601String(),
    };
  }

  AddressbookEntry copyWith({
    String? label,
    String? address,
    DateTime? createdAt,
  }) {
    return AddressbookEntry(
      label: label ?? this.label,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
