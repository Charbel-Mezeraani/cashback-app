// ─────────────────────────────────────────────────────────────────────────────
// All data models used across the app.
// Plain Dart classes with fromJson factories — no code generation needed.
// ─────────────────────────────────────────────────────────────────────────────

class User {
  final String id;
  final String email;
  final String? fullName;
  final String? phone;
  final bool phoneVerified;
  final bool onboardingCompleted;
  final String? city;
  final String? ageRange;
  final List<String> preferences;
  final String? country;
  final DateTime? dateOfBirth;

  const User({
    required this.id,
    required this.email,
    this.fullName,
    this.phone,
    this.phoneVerified       = false,
    this.onboardingCompleted = false,
    this.city,
    this.ageRange,
    this.preferences         = const [],
    this.country,
    this.dateOfBirth,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id:                   j['id']    as String,
        email:                j['email'] as String,
        fullName:             j['full_name']  as String?,
        phone:                j['phone']      as String?,
        phoneVerified:        (j['phone_verified']       as bool?) ?? false,
        onboardingCompleted:  (j['onboarding_completed'] as bool?) ?? false,
        city:                 j['city']       as String?,
        ageRange:             j['age_range']  as String?,
        preferences:          (j['preferences'] as List<dynamic>?)
                                  ?.map((e) => e as String).toList() ?? [],
        country:              j['country']        as String?,
        dateOfBirth:          j['date_of_birth'] != null
                                  ? DateTime.tryParse(j['date_of_birth'] as String)
                                  : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class Campaign {
  final String id;
  final String name;
  final String cashbackType; // 'fixed' | 'percent'
  final double cashbackValue;
  final double? maxCashback;
  final DateTime endsAt;

  const Campaign({
    required this.id,
    required this.name,
    required this.cashbackType,
    required this.cashbackValue,
    this.maxCashback,
    required this.endsAt,
  });

  factory Campaign.fromJson(Map<String, dynamic> j) => Campaign(
        id:            j['campaign_id']   as String,
        name:          j['campaign_name'] as String,
        cashbackType:  j['cashback_type'] as String,
        cashbackValue: double.parse(j['cashback_value'].toString()),
        maxCashback:   j['max_cashback'] != null
            ? double.parse(j['max_cashback'].toString())
            : null,
        endsAt: DateTime.parse(j['campaign_ends_at'] as String),
      );

  String get displayValue => cashbackType == 'fixed'
      ? '\$${cashbackValue.toStringAsFixed(2)} cashback'
      : '${cashbackValue.toStringAsFixed(0)}% cashback';
}

// ─────────────────────────────────────────────────────────────────────────────
// CampaignOffer — used on the home screen offers list.
// Combines campaign + product data from GET /products/campaigns/active.

class CampaignOffer {
  final String campaignId;
  final String campaignName;
  final String cashbackType;
  final double cashbackValue;
  final String productId;
  final String productName;
  final String? brand;
  final String? category;
  final String barcode;
  final String? imageUrl;

  const CampaignOffer({
    required this.campaignId,
    required this.campaignName,
    required this.cashbackType,
    required this.cashbackValue,
    required this.productId,
    required this.productName,
    this.brand,
    this.category,
    required this.barcode,
    this.imageUrl,
  });

  String get displayValue => cashbackType == 'fixed'
      ? '\$${cashbackValue.toStringAsFixed(2)} cashback'
      : '${cashbackValue.toStringAsFixed(0)}% cashback';

  factory CampaignOffer.fromJson(Map<String, dynamic> j) => CampaignOffer(
        campaignId:    j['campaign_id']   as String,
        campaignName:  j['campaign_name'] as String,
        cashbackType:  j['cashback_type'] as String,
        cashbackValue: double.parse(j['cashback_value'].toString()),
        productId:     j['product_id']   as String,
        productName:   j['product_name'] as String,
        brand:         j['brand']        as String?,
        category:      j['category']     as String?,
        barcode:       j['barcode']      as String,
        imageUrl:      j['image_url']    as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class Product {
  final String id;
  final String barcode;
  final String name;
  final String? brand;
  final String? category;
  final String? imageUrl;
  final DateTime eligibleFrom;
  final Campaign? campaign;

  const Product({
    required this.id,
    required this.barcode,
    required this.name,
    this.brand,
    this.category,
    this.imageUrl,
    required this.eligibleFrom,
    this.campaign,
  });

  bool get hasActiveCampaign => campaign != null;

  factory Product.fromJson(Map<String, dynamic> j) {
    final p = j['product'] as Map<String, dynamic>? ?? j;
    return Product(
      id:           p['id']           as String,
      barcode:      p['barcode']      as String,
      name:         p['name']         as String,
      brand:        p['brand']        as String?,
      category:     p['category']     as String?,
      imageUrl:     p['image_url']    as String?,
      eligibleFrom: DateTime.parse(p['eligible_from'] as String),
      campaign: p['campaign_id'] != null ? Campaign.fromJson(p) : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ReceiptItem {
  final String id;
  final String? description;
  final String? barcode;
  final double quantity;
  final double? unitPrice;
  final String? productId;
  final String? productName;

  const ReceiptItem({
    required this.id,
    this.description,
    this.barcode,
    required this.quantity,
    this.unitPrice,
    this.productId,
    this.productName,
  });

  bool get isMatched => productId != null;

  factory ReceiptItem.fromJson(Map<String, dynamic> j) => ReceiptItem(
        id:          j['id']           as String,
        description: j['description']  as String?,
        barcode:     j['barcode']      as String?,
        quantity:    double.parse((j['quantity'] ?? 1).toString()),
        unitPrice:   j['unit_price'] != null
            ? double.parse(j['unit_price'].toString())
            : null,
        productId:   j['product_id']   as String?,
        productName: j['product_name'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class Receipt {
  final String id;
  final String? storeName;
  final DateTime? purchaseDate;
  final double? totalAmount;
  final String ocrStatus; // 'pending' | 'processing' | 'done' | 'failed'
  final String? ocrError;
  final List<ReceiptItem> items;

  const Receipt({
    required this.id,
    this.storeName,
    this.purchaseDate,
    this.totalAmount,
    required this.ocrStatus,
    this.ocrError,
    this.items = const [],
  });

  bool get isDone       => ocrStatus == 'done';
  bool get isPending    => ocrStatus == 'pending' || ocrStatus == 'processing';
  bool get isFailed     => ocrStatus == 'failed';

  Receipt copyWith({String? ocrStatus, List<ReceiptItem>? items}) => Receipt(
        id:           id,
        storeName:    storeName,
        purchaseDate: purchaseDate,
        totalAmount:  totalAmount,
        ocrStatus:    ocrStatus ?? this.ocrStatus,
        ocrError:     ocrError,
        items:        items ?? this.items,
      );

  factory Receipt.fromJson(Map<String, dynamic> j) {
    final r = j['receipt'] as Map<String, dynamic>? ?? j;
    final rawItems = (j['items'] as List<dynamic>?) ?? [];
    return Receipt(
      id:           r['id']           as String,
      storeName:    r['store_name']   as String?,
      purchaseDate: r['purchase_date'] != null
          ? DateTime.parse(r['purchase_date'] as String)
          : null,
      totalAmount: r['total_amount'] != null
          ? double.parse(r['total_amount'].toString())
          : null,
      ocrStatus:  r['ocr_status']    as String,
      ocrError:   r['ocr_error']     as String?,
      items:      rawItems.map((e) => ReceiptItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class Claim {
  final String id;
  final String status; // 'pending' | 'approved' | 'rejected' | 'flagged'
  final double cashbackAmount;
  final int fraudScore;
  final List<String> flags;
  final DateTime submittedAt;

  const Claim({
    required this.id,
    required this.status,
    required this.cashbackAmount,
    required this.fraudScore,
    required this.flags,
    required this.submittedAt,
  });

  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isFlagged  => status == 'flagged';

  factory Claim.fromJson(Map<String, dynamic> j) => Claim(
        id:             j['claim_id']       as String,
        status:         j['status']         as String,
        cashbackAmount: double.parse(j['cashback_amount'].toString()),
        fraudScore:     j['fraud_score']    as int,
        flags:          (j['flags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        submittedAt: DateTime.now(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class WalletTransaction {
  final String id;
  final double amount;
  final String type;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> j) =>
      WalletTransaction(
        id:        j['id']     as String,
        amount:    double.parse(j['amount'].toString()),
        type:      j['type']   as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class Wallet {
  final double balance;
  final DateTime updatedAt;
  final List<WalletTransaction> transactions;

  const Wallet({
    required this.balance,
    required this.updatedAt,
    required this.transactions,
  });

  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        balance:   double.parse(j['balance'].toString()),
        updatedAt: DateTime.parse(j['updated_at'] as String),
        transactions: (j['transactions'] as List<dynamic>)
            .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
