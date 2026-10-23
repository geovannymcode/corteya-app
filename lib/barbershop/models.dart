class Barbershop {
  const Barbershop({
    required this.slug,
    required this.name,
    this.logoUrl,
    this.primaryColor,
    this.secondaryColor,
    required this.open,
    required this.statusMessage,
    this.nextChangeAt,
    required this.bookingEnabled,
  });
  final String slug, name, statusMessage;
  final String? logoUrl, primaryColor, secondaryColor;
  final bool open, bookingEnabled;
  final DateTime? nextChangeAt;
  factory Barbershop.fromJson(Map<String, dynamic> j) => Barbershop(
    slug: j['slug'] as String,
    name: j['name'] as String,
    logoUrl: j['logoUrl'] as String?,
    primaryColor: j['primaryColor'] as String?,
    secondaryColor: j['secondaryColor'] as String?,
    open: j['open'] as bool,
    statusMessage: j['statusMessage'] as String,
    nextChangeAt: j['nextChangeAt'] == null
        ? null
        : DateTime.parse(j['nextChangeAt'] as String),
    bookingEnabled: j['bookingEnabled'] as bool,
  );
}

class ShopService {
  const ShopService(this.id, this.name, this.durationMinutes, this.priceCop);
  final String id, name;
  final int durationMinutes, priceCop;
  factory ShopService.fromJson(Map<String, dynamic> j) => ShopService(
    j['id'] as String,
    j['name'] as String,
    j['durationMinutes'] as int,
    j['priceCop'] as int,
  );
}

class Barber {
  const Barber(this.id, this.name, this.photoUrl);
  final String id, name;
  final String? photoUrl;
  factory Barber.fromJson(Map<String, dynamic> j) =>
      Barber(j['id'] as String, j['name'] as String, j['photoUrl'] as String?);
}

class ShopContent {
  const ShopContent(this.shop, this.services, this.barbers);
  final Barbershop shop;
  final List<ShopService> services;
  final List<Barber> barbers;
}
