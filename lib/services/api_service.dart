import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import '../models/transaction.dart';

class ApiService {
  ApiService._internal();
  static final ApiService instance = ApiService._internal();

  final CollectionReference<Map<String, dynamic>> _txCol =
      FirebaseFirestore.instance.collection('transactions');

  /// Save a new transaction to Cloud Firestore.
  /// Returns the saved Transaction with the Firestore document ID.
  Future<Transaction> saveTransaction(Transaction tx) async {
    final docRef = _txCol.doc();
    final newTx = tx.copyWith(
      id: docRef.id,
      redeemed: false,
    );

    await docRef.set(newTx.toJson());
    return newTx;
  }

  /// Mark a transaction as redeemed in Cloud Firestore.
  Future<bool> redeemTransaction(String id) async {
    try {
      final docRef = _txCol.doc(id);
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        return false;
      }

      final data = snapshot.data();
      final isAlreadyRedeemed = data?['redeemed'] as bool? ?? false;
      if (isAlreadyRedeemed) {
        return false; // already redeemed
      }

      await docRef.update({
        'redeemed': true,
        'redeemedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetch all active (non-redeemed) transactions.
  Future<List<Transaction>> fetchActiveTransactions() async {
    try {
      final snapshot = await _txCol
          .where('redeemed', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Transaction.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Real-time stream of all transactions.
  Stream<List<Transaction>> streamTransactions() {
    return _txCol.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Transaction.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    });
  }
}