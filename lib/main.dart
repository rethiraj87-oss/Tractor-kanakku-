import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TractorApp());
}

class TractorApp extends StatelessWidget {
  const TractorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'டிராக்டர் கணக்கு',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green.shade700),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class RentalEntry {
  final String id;
  final String customerName;
  final String village;
  final String phone;
  final String date;
  final String workType;
  final String unit;
  final double quantity;
  final double rate;
  double paid;
  final String notes;

  RentalEntry({
    required this.id,
    required this.customerName,
    required this.village,
    required this.phone,
    required this.date,
    required this.workType,
    required this.unit,
    required this.quantity,
    required this.rate,
    required this.paid,
    required this.notes,
  });

  double get total => quantity * rate;
  double get balance => (total - paid) < 0 ? 0 : (total - paid);

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerName': customerName,
        'village': village,
        'phone': phone,
        'date': date,
        'workType': workType,
        'unit': unit,
        'quantity': quantity,
        'rate': rate,
        'paid': paid,
        'notes': notes,
      };

  factory RentalEntry.fromJson(Map<String, dynamic> json) => RentalEntry(
        id: json['id'] ?? '',
        customerName: json['customerName'] ?? '',
        village: json['village'] ?? '',
        phone: json['phone'] ?? '',
        date: json['date'] ?? '',
        workType: json['workType'] ?? 'ரோட்டாவேட்டர்',
        unit: json['unit'] ?? 'மணி',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
        rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
        paid: (json['paid'] as num?)?.toDouble() ?? 0.0,
        notes: json['notes'] ?? '',
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _storageKey = 'tractor_entries_v1';
  List<RentalEntry> _entries = [];
  String _searchQuery = '';
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final List decoded = jsonDecode(raw);
      _entries = decoded.map((e) => RentalEntry.fromJson(e)).toList();
    }
    setState(() => _loading = false);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  List<RentalEntry> get _filteredEntries {
    return _entries.where((e) {
      final q = _searchQuery.trim().toLowerCase();
      final matchesSearch = q.isEmpty ||
          e.customerName.toLowerCase().contains(q) ||
          e.village.toLowerCase().contains(q) ||
          e.phone.contains(q);
      if (!matchesSearch) return false;
      if (_filter == 'pending') return e.balance > 0;
      if (_filter == 'paid') return e.balance <= 0;
      return true;
    }).toList();
  }

  double get _totalAmount => _entries.fold(0, (s, e) => s + e.total);
  double get _totalPaid => _entries.fold(0, (s, e) => s + e.paid);
  double get _totalBalance => _entries.fold(0, (s, e) => s + e.balance);

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddEntrySheet(
        onSave: (entry) {
          setState(() => _entries.insert(0, entry));
          _saveData();
        },
      ),
    );
  }

  void _openPaymentDialog(RentalEntry entry) {
    final ctrl = TextEditingController(text: entry.balance.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('வரவு சேர் - ${entry.customerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('மீதி பாக்கி: ₹${entry.balance.toStringAsFixed(0)}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'பெற்ற தொகை (₹)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ரத்து'),
          ),
          FilledButton(
            onPressed: () {
              final amt = double.tryParse(ctrl.text.trim()) ?? 0;
              if (amt > 0) {
                setState(() => entry.paid += amt);
                _saveData();
              }
              Navigator.pop(ctx);
            },
            child: const Text('சேமி'),
          ),
        ],
      ),
    );
  }

  void _copyBill(RentalEntry entry) {
    final bill = '''டிராக்டர் வாடகை பில்
தேதி: ${entry.date}
பெயர்: ${entry.customerName}${entry.village.isNotEmpty ? ' (${entry.village})' : ''}
வேலை: ${entry.workType}
அளவு: ${entry.quantity} ${entry.unit} x ₹${entry.rate.toStringAsFixed(0)}
மொத்தம்: ₹${entry.total.toStringAsFixed(0)}
வரவு: ₹${entry.paid.toStringAsFixed(0)}
பாக்கி: ₹${entry.balance.toStringAsFixed(0)}''';

    Clipboard.setData(ClipboardData(text: bill));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('பில் காப்பி செய்யப்பட்டது! WhatsApp-ல் பேஸ்ட் செய்யலாம்.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _confirmDelete(RentalEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('பதிவை நீக்கவா?'),
        content: Text('${entry.customerName} (${entry.date}) கணக்கை நீக்க வேண்டுமா?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('இல்லை'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() => _entries.removeWhere((e) => e.id == entry.id));
              _saveData();
              Navigator.pop(ctx);
            },
            child: const Text('நீக்கு'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('டிராக்டர் வாடகை கணக்கு'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.green.shade50,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _summaryBox('மொத்தம்', _totalAmount, Colors.blue.shade800),
                      const SizedBox(width: 8),
                      _summaryBox('வரவு', _totalPaid, Colors.green.shade800),
                      const SizedBox(width: 8),
                      _summaryBox('பாக்கி', _totalBalance, Colors.red.shade700),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'பெயர் / ஊர் / எண் தேடு...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      _filterChip('அனைத்தும்', 'all'),
                      const SizedBox(width: 8),
                      _filterChip('பாக்கி', 'pending'),
                      const SizedBox(width: 8),
                      _filterChip('முடிந்தது', 'paid'),
                    ],
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const Center(
                          child: Text(
                            'கணக்கு எதுவும் இல்லை.\nகீழே உள்ள + பட்டனை அழுத்தி சேர்க்கவும்.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final item = list[i];
                            final isPending = item.balance > 0;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.customerName,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          item.date,
                                          style: TextStyle(color: Colors.grey.shade700),
                                        ),
                                      ],
                                    ),
                                    if (item.village.isNotEmpty || item.phone.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          [item.village, item.phone]
                                              .where((s) => s.isNotEmpty)
                                              .join(' • '),
                                          style: TextStyle(color: Colors.grey.shade700),
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${item.workType}  |  ${item.quantity} ${item.unit} × ₹${item.rate.toStringAsFixed(0)}',
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                    if (item.notes.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'குறிப்பு: ${item.notes}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ),
                                    const Divider(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('மொத்தம்: ₹${item.total.toStringAsFixed(0)}'),
                                        Text(
                                          'வரவு: ₹${item.paid.toStringAsFixed(0)}',
                                          style: TextStyle(color: Colors.green.shade800),
                                        ),
                                        Text(
                                          'பாக்கி: ₹${item.balance.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isPending
                                                ? Colors.red.shade700
                                                : Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (isPending)
                                          TextButton.icon(
                                            onPressed: () => _openPaymentDialog(item),
                                            icon: const Icon(Icons.payments_outlined, size: 18),
                                            label: const Text('வரவு சேர்'),
                                          ),
                                        TextButton.icon(
                                          onPressed: () => _copyBill(item),
                                          icon: const Icon(Icons.copy, size: 18),
                                          label: const Text('பில்'),
                                        ),
                                        IconButton(
                                          onPressed: () => _confirmDelete(item),
                                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('புதிய கணக்கு'),
      ),
    );
  }

  Widget _summaryBox(String label, double value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              '₹${value.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String key) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == key,
      onSelected: (_) => setState(() => _filter = key),
    );
  }
}

class AddEntrySheet extends StatefulWidget {
  final void Function(RentalEntry) onSave;
  const AddEntrySheet({super.key, required this.onSave});

  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _villageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _paidCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String _workType = 'ரோட்டாவேட்டர்';
  String _unit = 'மணி';

  final List<String> _workTypes = [
    'ரோட்டாவேட்டர்',
    'உழவு / கலப்பை',
    '5 கொத்து / 9 கொத்து',
    'டிரெய்லர் / டிப்பர்',
    'லெவலர்',
    'மற்றவை',
  ];

  final List<String> _units = ['மணி', 'ஏக்கர்', 'நடை'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _villageCtrl.dispose();
    _phoneCtrl.dispose();
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    _paidCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _formattedDate =>
      '${_selectedDate.day.toString().padLeft(2, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.year}';

  double get _total {
    final q = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final r = double.tryParse(_rateCtrl.text.trim()) ?? 0;
    return q * r;
  }

  double get _balance {
    final p = double.tryParse(_paidCtrl.text.trim()) ?? 0;
    return (_total - p) < 0 ? 0 : (_total - p);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final entry = RentalEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      customerName: _nameCtrl.text.trim(),
      village: _villageCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      date: _formattedDate,
      workType: _workType,
      unit: _unit,
      quantity: double.tryParse(_qtyCtrl.text.trim()) ?? 0,
      rate: double.tryParse(_rateCtrl.text.trim()) ?? 0,
      paid: double.tryParse(_paidCtrl.text.trim()) ?? 0,
      notes: _notesCtrl.text.trim(),
    );
    widget.onSave(entry);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignm
