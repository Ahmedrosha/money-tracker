import 'package:flutter/material.dart';

/// Icons are stored by key (not code point) so release builds can
/// tree-shake the icon font.
const Map<String, IconData> kCategoryIcons = {
  'food': Icons.restaurant,
  'groceries': Icons.shopping_cart,
  'transport': Icons.directions_car,
  'fuel': Icons.local_gas_station,
  'home': Icons.home,
  'bills': Icons.receipt_long,
  'phone': Icons.phone_android,
  'internet': Icons.wifi,
  'health': Icons.local_hospital,
  'shopping': Icons.shopping_bag,
  'clothes': Icons.checkroom,
  'entertainment': Icons.movie,
  'travel': Icons.flight,
  'education': Icons.school,
  'gift': Icons.card_giftcard,
  'kids': Icons.child_care,
  'pets': Icons.pets,
  'sport': Icons.fitness_center,
  'coffee': Icons.local_cafe,
  'charity': Icons.volunteer_activism,
  'fees': Icons.account_balance,
  'salary': Icons.work,
  'bonus': Icons.star,
  'business': Icons.business_center,
  'interest': Icons.trending_up,
  'refund': Icons.undo,
  'other': Icons.category,
};

IconData categoryIcon(String key) => kCategoryIcons[key] ?? Icons.category;

const List<int> kCategoryColors = [
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF5E35B1,
  0xFF3949AB,
  0xFF1E88E5,
  0xFF039BE5,
  0xFF00897B,
  0xFF43A047,
  0xFF7CB342,
  0xFFFDD835,
  0xFFFFB300,
  0xFFFB8C00,
  0xFFF4511E,
  0xFF6D4C41,
  0xFF607D8B,
];
