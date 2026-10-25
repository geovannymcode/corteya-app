class Membership {
  const Membership({
    required this.barbershopId,
    required this.role,
    this.barbershopSlug,
    this.barbershopName,
    this.barberId,
  });
  final String barbershopId, role;
  // Se admiten ausentes para no atribuir permisos por error con el contrato anterior.
  final String? barbershopSlug, barbershopName, barberId;
  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
    barbershopId: j['barbershopId'] as String,
    role: j['role'] as String,
    barbershopSlug: j['barbershopSlug'] as String?,
    barbershopName: j['barbershopName'] as String?,
    barberId: j['barberId'] as String?,
  );
}

class Profile {
  const Profile(this.id, this.name, this.memberships);
  final String id;
  final String? name;
  final List<Membership> memberships;
  bool staffOf(String? slug) =>
      slug != null &&
      memberships.any(
        (m) => m.barbershopSlug == slug && ['OWNER', 'BARBER'].contains(m.role),
      );
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    j['id'] as String,
    j['name'] as String?,
    (j['memberships'] as List)
        .map((m) => Membership.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
  );
}
