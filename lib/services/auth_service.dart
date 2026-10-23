import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vendor.dart';
import '../models/employee.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // ---------- Hardcoded admin credentials ----------
  static const String adminUsername = 'admin';
  static const String adminPassword = 'admin123';

  final CollectionReference<Map<String, dynamic>> _vendorCol =
      FirebaseFirestore.instance.collection('vendors');
  final CollectionReference<Map<String, dynamic>> _employeeCol =
      FirebaseFirestore.instance.collection('employees');

  // Local cache kept in sync with Firestore for instant synchronous reads
  List<Vendor> _vendors = [];
  List<Employee> _employees = [];

  bool _initialized = false;

  /// Initialize real-time sync with Firestore for Vendors and Employees
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Listen to vendors collection
    _vendorCol.snapshots().listen((snapshot) {
      _vendors = snapshot.docs.map((doc) {
        final data = doc.data();
        return Vendor.fromJson({...data, 'id': doc.id});
      }).toList();
    });

    // Listen to employees collection
    _employeeCol.snapshots().listen((snapshot) {
      _employees = snapshot.docs.map((doc) {
        final data = doc.data();
        return Employee.fromJson({...data, 'id': doc.id});
      }).toList();
    });

    // Initial fetch to ensure cache is populated
    final vSnap = await _vendorCol.get();
    _vendors = vSnap.docs.map((doc) {
      final data = doc.data();
      return Vendor.fromJson({...data, 'id': doc.id});
    }).toList();

    final eSnap = await _employeeCol.get();
    _employees = eSnap.docs.map((doc) {
      final data = doc.data();
      return Employee.fromJson({...data, 'id': doc.id});
    }).toList();

    // Seed default vendor and employee if none exist
    if (!vendorUsernameExists('vendor1')) {
      final v = await addVendor(username: 'vendor1', password: 'vendor1');
      await addEmployee(
        vendorId: v.id,
        username: 'emp1',
        password: 'emp1',
      );
    }
  }

  // ---------- Admin ----------
  bool adminLogin(String username, String password) {
    return username.trim() == adminUsername &&
        password.trim() == adminPassword;
  }

  // ---------- Vendors ----------
  List<Vendor> get vendors => List.unmodifiable(_vendors);

  bool vendorUsernameExists(String username, {String? ignoreId}) {
    return _vendors.any(
      (v) =>
          v.username.toLowerCase() == username.trim().toLowerCase() &&
          v.id != ignoreId,
    );
  }

  Future<Vendor> addVendor({required String username, required String password}) async {
    final docRef = _vendorCol.doc();
    final vendor = Vendor(
      id: docRef.id,
      username: username.trim(),
      password: password.trim(),
    );

    // Save permanently in Cloud Firestore
    await docRef.set(vendor.toJson());
    if (!_vendors.any((v) => v.id == vendor.id)) {
      _vendors.add(vendor);
    }
    return vendor;
  }

  Future<void> updateVendor(String id, {String? username, String? password}) async {
    final Map<String, dynamic> updates = {};
    if (username != null && username.trim().isNotEmpty) {
      updates['username'] = username.trim();
    }
    if (password != null && password.trim().isNotEmpty) {
      updates['password'] = password.trim();
    }

    if (updates.isNotEmpty) {
      await _vendorCol.doc(id).update(updates);
      final idx = _vendors.indexWhere((v) => v.id == id);
      if (idx != -1) {
        if (updates.containsKey('username')) _vendors[idx].username = updates['username'];
        if (updates.containsKey('password')) _vendors[idx].password = updates['password'];
      }
    }
  }

  Future<void> deleteVendor(String id) async {
    await _vendorCol.doc(id).delete();
    _vendors.removeWhere((v) => v.id == id);

    // Also remove vendor's employees
    final emps = _employees.where((e) => e.vendorId == id).toList();
    for (final emp in emps) {
      await deleteEmployee(emp.id);
    }
  }

  Vendor? findVendorById(String id) {
    for (final v in _vendors) {
      if (v.id == id) return v;
    }
    return null;
  }

  Vendor? vendorLogin(String username, String password) {
    for (final v in _vendors) {
      if (v.username.toLowerCase() == username.trim().toLowerCase() &&
          v.password == password.trim()) {
        return v;
      }
    }
    return null;
  }

  // ---------- Employees ----------
  List<Employee> employeesOf(String vendorId) =>
      _employees.where((e) => e.vendorId == vendorId).toList();

  bool employeeUsernameExists(String vendorId, String username, {String? ignoreId}) {
    return _employees.any(
      (e) =>
          e.vendorId == vendorId &&
          e.username.toLowerCase() == username.trim().toLowerCase() &&
          e.id != ignoreId,
    );
  }

  Future<Employee> addEmployee({
    required String vendorId,
    required String username,
    required String password,
  }) async {
    final docRef = _employeeCol.doc();
    final emp = Employee(
      id: docRef.id,
      username: username.trim(),
      password: password.trim(),
      vendorId: vendorId,
    );

    // Save permanently in Cloud Firestore
    await docRef.set(emp.toJson());
    if (!_employees.any((e) => e.id == emp.id)) {
      _employees.add(emp);
    }
    return emp;
  }

  Future<void> updateEmployee(String id, {String? username, String? password}) async {
    final Map<String, dynamic> updates = {};
    if (username != null && username.trim().isNotEmpty) {
      updates['username'] = username.trim();
    }
    if (password != null && password.trim().isNotEmpty) {
      updates['password'] = password.trim();
    }

    if (updates.isNotEmpty) {
      await _employeeCol.doc(id).update(updates);
      final idx = _employees.indexWhere((e) => e.id == id);
      if (idx != -1) {
        if (updates.containsKey('username')) _employees[idx].username = updates['username'];
        if (updates.containsKey('password')) _employees[idx].password = updates['password'];
      }
    }
  }

  Future<void> deleteEmployee(String id) async {
    await _employeeCol.doc(id).delete();
    _employees.removeWhere((e) => e.id == id);
  }

  Employee? employeeLogin(String username, String password) {
    for (final e in _employees) {
      if (e.username.toLowerCase() == username.trim().toLowerCase() &&
          e.password == password.trim()) {
        return e;
      }
    }
    return null;
  }
}