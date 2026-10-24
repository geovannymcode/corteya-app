/// Web Checkout parameters come signed by the backend. Never generate a signature
/// or alter signed amounts/references/expiration dates in the client.
Uri wompiCheckoutUri(String checkoutUrl, Map<String, String> parameters) {
  final base = Uri.parse(checkoutUrl);
  if (base.scheme != 'https' ||
      base.host != 'checkout.wompi.co' ||
      base.path != '/p/' ||
      base.userInfo.isNotEmpty ||
      base.hasFragment ||
      base.hasQuery ||
      base.port != 443) {
    throw const FormatException('Checkout no válido');
  }
  const required = [
    'public-key',
    'currency',
    'amount-in-cents',
    'reference',
    'signature:integrity',
    'redirect-url',
    'expiration-time',
  ];
  if (required.any((key) => parameters[key]?.isNotEmpty != true) ||
      parameters['currency'] != 'COP' ||
      !RegExp(r'^\d+$').hasMatch(parameters['amount-in-cents'] ?? '') ||
      !RegExp(r'^[a-fA-F0-9]{64}$')
          .hasMatch(parameters['signature:integrity'] ?? '')) {
    throw const FormatException('Faltan datos del pago');
  }
  return base.replace(queryParameters: parameters);
}

int remainingCop(int priceCop, int depositCop) {
  if (priceCop < 0 || depositCop < 0 || depositCop > priceCop) {
    throw const FormatException('Montos de la reserva no válidos');
  }
  return priceCop - depositCop;
}
