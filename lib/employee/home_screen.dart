import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../widgets/transaction_row.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService.instance;

  /// Map roll -> {transaction, status}
  final Map<String, Transaction> _transactions = {};
  final Map<String, RowStatus> _statuses = {};

  bool _isScanning = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToTransactions();
  }

  void _listenToTransactions() {
    _api.streamTransactions().listen((txList) {
      if (!mounted) return;
      setState(() {
        for (final tx in txList) {
          if (!tx.redeemed) {
            // Keep existing status if row was already pending or saving
            final currentStatus = _statuses[tx.rollNumber];
            if (currentStatus != RowStatus.saving &&
                currentStatus != RowStatus.redeeming) {
              _transactions[tx.rollNumber] = tx;
              _statuses[tx.rollNumber] = RowStatus.saved;
            }
          } else {
            // If redeemed in backend, remove from active list
            _transactions.remove(tx.rollNumber);
            _statuses.remove(tx.rollNumber);
          }
        }
        _isLoading = false;
      });
    }, onError: (err) {
      debugPrint('Error streaming transactions: $err');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  // ---------- Scanning ----------
  Future<void> _startScanner() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    try {
      final roll = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const ScannerScreen()),
      );

      if (roll == null || roll.isEmpty) return;

      if (_transactions.containsKey(roll)) {
        _showSnack(
          'Roll number $roll is already in the list.',
          color: Colors.orange.shade700,
        );
        return;
      }

      setState(() {
        _transactions[roll] = Transaction(rollNumber: roll, amount: 0);
        _statuses[roll] = RowStatus.pending;
      });

      _showSnack('Scanned: $roll', color: Colors.green.shade700);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // ---------- Save ----------
  Future<void> _save(String roll, double amount) async {
    setState(() => _statuses[roll] = RowStatus.saving);
    try {
      final saved = await _api.saveTransaction(
        _transactions[roll]!.copyWith(amount: amount),
      );
      setState(() {
        _transactions[roll] = saved;
        _statuses[roll] = RowStatus.saved;
      });
      _showSnack(
        '₹${_formatAmount(amount)} saved for $roll.',
        color: Colors.green.shade700,
      );
    } catch (e) {
      setState(() => _statuses[roll] = RowStatus.pending);
      _showSnack('Failed to save: $e', color: Colors.red.shade700);
    }
  }

  // ---------- Redeem ----------
  Future<void> _redeem(String roll) async {
    final tx = _transactions[roll]!;
    final amountStr = _formatAmount(tx.amount);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Redemption'),
        content: Text(
          'Are you sure you want to redeem ₹$amountStr for roll number $roll?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Redeem'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _statuses[roll] = RowStatus.redeeming);
    try {
      final ok = await _api.redeemTransaction(tx.id!);
      if (!ok) throw Exception('Backend refused redemption');

      setState(() {
        _transactions.remove(roll);
        _statuses.remove(roll);
      });

      _showSnack(
        '₹$amountStr redeemed successfully for $roll.',
        color: Colors.green.shade700,
      );
    } catch (e) {
      setState(() => _statuses[roll] = RowStatus.saved);
      _showSnack('Redeem failed: $e', color: Colors.red.shade700);
    }
  }

  // ---------- Helpers ----------
  String _formatAmount(double v) {
    if (v.truncateToDouble() == v) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  double get _totalPending {
    return _transactions.values
        .where((t) => t.amount > 0)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final rolls = _transactions.keys.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildActionsBar(),
            _buildTableHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : rolls.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: rolls.length,
                          itemBuilder: (context, i) {
                            final roll = rolls[i];
                            return TransactionRow(
                              key: ValueKey(roll),
                              transaction: _transactions[roll]!,
                              status: _statuses[roll] ?? RowStatus.pending,
                              onSave: (amount) => _save(roll, amount),
                              onRedeem: () => _redeem(roll),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.qr_code_2,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'StudentPay',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              Text(
                'QR Payment & Redemption',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.currency_rupee,
                    size: 16, color: Color(0xFF2563EB)),
                const SizedBox(width: 4),
                Text(
                  _formatAmount(_totalPending),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2563EB),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'pending',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF2563EB)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _startScanner,
              icon: _isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.qr_code_scanner),
              label: Text(_isScanning ? 'Opening...' : 'Start Scanner'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _transactions.clear();
                _statuses.clear();
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Clear'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  vertical: 16, horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'ROLL NUMBER',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'AMOUNT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_scanner,
              size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No students scanned yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Click "Start Scanner" and hold a student ID card\nin front of the camera.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}