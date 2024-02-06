import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Check the platform
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
  }
  runApp(const MyApp());
}

class AttendanceRecord {
  String studentName;
  String status;
  final String date;

  AttendanceRecord({
    required this.studentName,
    required this.status,
    required this.date,
  });
}

class AttendanceScreen extends StatefulWidget {
  final String subjectCode;
  final String role;
  final String teacherUsername;
  final DatabaseHelper databaseHelper;

  const AttendanceScreen(
    this.subjectCode,
    this.role, {
    super.key,
    required this.teacherUsername,
    required this.databaseHelper,
  });

  @override
  AttendanceScreenState createState() => AttendanceScreenState();
}

class AttendanceScreenState extends State<AttendanceScreen> {
  List<Student> students = [];
  List<Student> filteredStudents = [];
  List<AttendanceRecord> attendanceRecords = [];

  bool _canEditStatus = false;

  final TextEditingController _searchController = TextEditingController();
  late final DatabaseHelper _databaseHelper;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.subjectCode,
            style: const TextStyle(color: Color(0xffBEA18E)),
          ),
          backgroundColor: const Color(0xFF45191C),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await loadData();
            resetStudentStatus();
          },
          child: Column(
            children: [
              if (students.isNotEmpty) _buildSearchField(),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredStudents.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.0),
                        color: const Color(0xFF826B5D),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _showStudentNamePopup(
                                    context, filteredStudents[index].name);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10.0),
                                  color: const Color(0xffBEA18E),
                                ),
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  filteredStudents[index].name,
                                  style: const TextStyle(fontSize: 12.0),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          if (_canEditStatus)
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10.0),
                                  color: const Color(0xffBEA18E),
                                ),
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  filteredStudents[index].status,
                                  style: const TextStyle(fontSize: 12.0),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10.0),
                                color: const Color(0xffBEA18E),
                              ),
                              child: Row(
                                children: [
                                  Visibility(
                                    visible: _canEditStatus,
                                    child: PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.arrow_drop_down,
                                        color: Color(0xFF45191C),
                                      ),
                                      itemBuilder: (BuildContext context) {
                                        return [
                                          'Present',
                                          'Not Present',
                                          'Excused'
                                        ]
                                            .map((status) =>
                                                PopupMenuItem<String>(
                                                  value: status,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(status),
                                                      if (_canEditStatus &&
                                                          filteredStudents[
                                                                      index]
                                                                  .status ==
                                                              status)
                                                        const Icon(Icons.check,
                                                            color: Color(
                                                                0xFF45191C)),
                                                    ],
                                                  ),
                                                ))
                                            .toList();
                                      },
                                      onSelected: (newStatus) {
                                        if (_canEditStatus) {
                                          setState(() {
                                            // Update the status of the selected student
                                            filteredStudents[index].status =
                                                newStatus;
                                            updateAttendance(
                                                filteredStudents[index].name,
                                                newStatus);
                                            saveData();
                                          });
                                        }
                                      },
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10.0),
                                      ),
                                      color: const Color(0xffBEA18E),
                                    ),
                                  ),
                                  if (_canEditStatus)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Color(0xFF45191C),
                                      ),
                                      onPressed: () {
                                        _showDeleteStudentDialog(
                                          context,
                                          student: filteredStudents[index],
                                        );
                                      },
                                    ),
                                  const SizedBox(width: 8.0),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.history,
                                      color: Color(0xFF45191C),
                                    ),
                                    onPressed: () {
                                      _showAttendanceHistoryDialog(
                                        context,
                                        student: filteredStudents[index],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ));
  }

  @override
  void initState() {
    super.initState();
    _databaseHelper = widget.databaseHelper;
    loadData();
    resetStudentStatus();
  }

  Future<bool> isTeachingSubject(String subjectCode) async {
    final List<Teacher> teachers =
        await _databaseHelper.getTeachers(subjectCode);

    // Check if the teacher's username matches any teacher for the subject
    return teachers.any((teacher) =>
        teacher.name.toLowerCase() == widget.teacherUsername.toLowerCase());
  }

  loadData() async {
    await _databaseHelper.createAttendanceTable();
    students = await _databaseHelper.getStudents(widget.subjectCode);
    attendanceRecords =
        await _databaseHelper.getAttendanceRecords(widget.subjectCode);

    // Determine user role and set _canEditStatus
    _canEditStatus =
        widget.role == 'Teacher' && await isTeachingSubject(widget.subjectCode);
    // Only update filteredStudents if there are existing students
    if (students.isNotEmpty) {
      filteredStudents = List.from(students);
    }

    setState(() {});
  }

  void resetStudentStatus() async {
    DateTime now = DateTime.now();
    String formattedDate = DateFormat('yyyy-MM-dd').format(now);

    // Iterate through students and update their status if needed
    for (var student in students) {
      int existingRecordIndex = attendanceRecords.indexWhere((record) =>
          record.studentName == student.name && record.date == formattedDate);

      if (existingRecordIndex == -1) {
        // Insert a new attendance record with default status
        await _databaseHelper.insertAttendanceRecord(
          widget.subjectCode,
          student.name,
          '',
          formattedDate,
        );
        // Update the local attendanceRecords list
        attendanceRecords.add(AttendanceRecord(
          studentName: student.name,
          status: '',
          date: formattedDate,
        ));
      }
    }

    // Update the filtered students list
    filteredStudents = List.from(students);
    setState(() {});
  }

  saveData() async {
    await _databaseHelper.deleteAllStudents(widget.subjectCode);

    for (var student in students) {
      await _databaseHelper.insertStudent(student, widget.subjectCode);
    }
  }

  Future<void> updateAttendance(String studentName, String newStatus) async {
    DateTime now = DateTime.now();
    String formattedDate = DateFormat('yyyy-MM-dd').format(now);

    int existingRecordIndex = attendanceRecords.indexWhere((record) =>
        record.studentName == studentName && record.date == formattedDate);
    if (existingRecordIndex != -1) {
      // Update the existing record
      attendanceRecords[existingRecordIndex].status = newStatus;
      await _databaseHelper.updateAttendanceRecord(
        widget.subjectCode,
        studentName,
        newStatus,
        formattedDate,
      );
    } else {
      // Insert a new attendance record
      await _databaseHelper.insertAttendanceRecord(
        widget.subjectCode,
        studentName,
        newStatus,
        formattedDate,
      );
      // Update the local attendanceRecords list
      attendanceRecords.add(AttendanceRecord(
        studentName: studentName,
        status: newStatus,
        date: formattedDate,
      ));
    }
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        onChanged: (query) {
          _filterStudents(query);
        },
        decoration: const InputDecoration(
          labelText: 'Search',
          filled: true,
          fillColor: Color(0xffBEA18E),
          suffixIcon: Icon(
            Icons.search,
            color: Color(0xFF45191C),
          ),
        ),
      ),
    );
  }

  void _filterStudents(String query) {
    setState(() {
      if (query.isEmpty) {
        // If the query is empty, show all students
        filteredStudents = List.from(students);
      } else {
        // Filter students based on the search query
        filteredStudents = students
            .where((student) =>
                student.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _showAttendanceHistoryDialog(BuildContext context,
      {required Student student}) {
    List<AttendanceRecord> studentAttendanceRecords = attendanceRecords
        .where((record) => record.studentName == student.name)
        .toList();

    int presentCount = studentAttendanceRecords
        .where((record) => record.status == 'Present')
        .length;

    List<AttendanceRecord> filteredRecords =
        List.from(studentAttendanceRecords);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xffBEA18E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  'Attendance History',
                                  style: TextStyle(
                                    fontSize: 20.0,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF45191C),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text(
                                  'Present Count: $presentCount',
                                  style: const TextStyle(
                                      fontSize: 18.0, color: Colors.black),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF45191C),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        onChanged: (query) {
                          setState(() {
                            filteredRecords = studentAttendanceRecords
                                .where((record) => record.date.contains(query))
                                .toList();
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Search by date',
                          prefixIcon: Icon(
                            Icons.search,
                            color: Color(0xFF45191C),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 300,
                      child: ListView.builder(
                        itemCount: filteredRecords.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(
                              'Status: ${filteredRecords[index].status}',
                              style: const TextStyle(
                                color: Color(0xFF45191C),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Date: ${filteredRecords[index].date}',
                              style: const TextStyle(
                                color: Colors.black,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showDeleteStudentDialog(BuildContext context,
      {required Student student}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xffBEA18E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        title: const Text(
          'Delete Student',
          style: TextStyle(
            color: Color(0xFF45191C),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text('Are you sure you want to delete ${student.name}?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF45191C),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              setState(() {
                // Remove the selected student from the list
                students.remove(student);
                filteredStudents.remove(student);
                saveData();
              });
              Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Color(0xFF45191C),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // Function to show the student name popup
  void _showStudentNamePopup(BuildContext context, String fullName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xffBEA18E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
          title: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info, color: Color(0xFF45191C)),
              SizedBox(width: 8.0),
              Text(
                'Student Name',
                style: TextStyle(
                  fontSize: 20.0,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF45191C),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(
                fullName,
                style: const TextStyle(fontSize: 20.0),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Color(0xFF45191C),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

  Future<void> createAttendanceTable() async {
    final Database db = await database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subjectCode TEXT,
        studentName TEXT,
        status TEXT,
        date TEXT
      )
    ''');
  }

  Future<void> deleteAllStudents(String subjectCode) async {
    final Database db = await database;

    await db.delete(
      'students',
      where: 'subjectCode = ?',
      whereArgs: [subjectCode],
    );
  }

  Future<void> deleteStudent(String studentName, String role) async {
    final Database db = await database;

    // Delete student from the students table
    await db.delete(
      'students',
      where: 'LOWER(name) = ?',
      whereArgs: [studentName.toLowerCase()],
    );
    if (role == 'Regular Student') {
      // Delete user from the users table
      await db.delete(
        'users',
        where: 'LOWER(username) = ? AND role = ?',
        whereArgs: [studentName.toLowerCase(), 'Regular Student'],
      );
    } else {
      // Delete user from the users table
      await db.delete(
        'users',
        where: 'LOWER(username) = ? AND role = ?',
        whereArgs: [studentName.toLowerCase(), 'Irregular Student'],
      );
    }
  }

  Future<void> deleteTeacher(String username) async {
    final Database db = await database;

    // Delete teacher from the teachers table
    await db.delete(
      'teachers',
      where: 'LOWER(name) = ?',
      whereArgs: [username.toLowerCase()],
    );
    // Delete user from the users table
    await db.delete(
      'users',
      where: 'LOWER(username) = ? AND role = ?',
      whereArgs: [username.toLowerCase(), 'Teacher'],
    );
  }

  Future<List<AttendanceRecord>> getAttendanceRecords(
      String subjectCode) async {
    final Database db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'attendance',
      where: 'subjectCode = ?',
      whereArgs: [subjectCode],
    );

    return List.generate(maps.length, (index) {
      return AttendanceRecord(
        studentName: maps[index]['studentName'],
        status: maps[index]['status'],
        date: maps[index]['date'],
      );
    });
  }

  Future<List<String>> getAvailableSubjects() async {
    final Database db = await database;

    // Get the list of subjects that are not picked by any teacher
    final List<Map<String, dynamic>> pickedSubjects =
        await db.query('teachers');
    List<String> pickedSubjectCodes = pickedSubjects
        .map((teacher) => teacher['subjectCode'] as String)
        .toList();

    // Get the complete list of subjects
    List<String> allSubjects = [
      'IM211',
      'CC214',
      'NET212',
      'GE105',
      'GE106',
      'GENSOC',
      'PE3',
      'ITELECTV'
    ];

    // Filter out the subjects that are already picked
    List<String> availableSubjects = allSubjects
        .where((subject) => !pickedSubjectCodes.contains(subject))
        .toList();

    return availableSubjects;
  }

  Future<String> getDatabasePath() async {
    final databasesPath = await getDatabasesPath();
    final String path = join(databasesPath, 'attendify.db');
    return path;
  }

  Future<List<Student>> getStudents(String subjectCode) async {
    final Database db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'students',
      where: 'subjectCode = ?',
      whereArgs: [subjectCode],
    );

    return List.generate(maps.length, (index) {
      return Student(
        name: maps[index]['name'],
        status: maps[index]['status'],
        firstQuarterGrade: maps[index]['firstQuarterGrade'],
        secondQuarterGrade: maps[index]['secondQuarterGrade'],
        thirdQuarterGrade: maps[index]['thirdQuarterGrade'],
        fourthQuarterGrade: maps[index]['fourthQuarterGrade'],
      );
    });
  }

  Future<List<Teacher>> getTeachers(String subjectCode) async {
    final Database db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'teachers',
      where: 'subjectCode = ?',
      whereArgs: [subjectCode],
    );

    return List.generate(maps.length, (index) {
      return Teacher(
        name: maps[index]['name'],
      );
    });
  }

  Future<void> insertAttendanceRecord(String subjectCode, String studentName,
      String status, String date) async {
    final Database db = await database;

    await db.insert(
      'attendance',
      {
        'subjectCode': subjectCode,
        'studentName': studentName,
        'status': status,
        'date': date,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertStudent(Student student, String subjectCode) async {
    final Database db = await database;

    await db.insert(
      'students',
      student.toMap(subjectCode),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertTeacher(Teacher teacher, String subjectCode) async {
    final Database db = await database;

    await db.insert(
      'teachers',
      teacher.toMap(subjectCode),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertUser(String username, String password, String role) async {
    final Database db = await database;

    // Hash the password before storing it
    String hashedPassword = sha256.convert(utf8.encode(password)).toString();

    await db.insert(
      'users',
      {'username': username, 'password': hashedPassword, 'role': role},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (role == 'student') {
      // Get the list of subjects
      List<String> subjects = [
        'IM211',
        'CC214',
        'NET212',
        'GE105',
        'GE106',
        'GENSOC',
        'PE3',
        'ITELECTV',
      ];

      // Insert the student into the students table for each subject
      for (String subjectCode in subjects) {
        await db.insert(
          'students',
          {
            'subjectCode': subjectCode,
            'name': username,
            'status': 'Present',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  Future<bool> isUsernameTaken(String username) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'LOWER(username) = ?',
      whereArgs: [username.toLowerCase()],
    );

    return result.isNotEmpty;
  }

  Future<void> updateAttendanceRecord(String subjectCode, String studentName,
      String status, String date) async {
    final Database db = await database;

    await db.update(
      'attendance',
      {'status': status},
      where: 'subjectCode = ? AND studentName = ? AND date = ?',
      whereArgs: [subjectCode, studentName, date],
    );
  }

  Future<void> updateAttendanceRecordStudentName(
      String subjectCode, String oldStudentName, String newStudentName) async {
    final Database db = await database;

    await db.rawUpdate('''
      UPDATE attendance
      SET studentName = ?
      WHERE subjectCode = ? AND studentName = ?
    ''', [newStudentName, subjectCode, oldStudentName]);
  }

  Future<String?> validateUser(
      String username, String password, String role) async {
    final Database db = await database;

    // Hash the entered password before comparing
    String hashedPassword = sha256.convert(utf8.encode(password)).toString();

    final List<Map<String, dynamic>> result = await db.query(
      'users',
      columns: ['role'],
      where: 'LOWER(username) = ? AND password = ? AND role = ?',
      whereArgs: [username.toLowerCase(), hashedPassword, role],
    );

    if (result.isNotEmpty) {
      return result[0]['role'] as String?;
    } else {
      return null;
    }
  }

  Future<void> _closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      // Close the database only if the app is terminated
      if (Platform.isAndroid || Platform.isIOS) {
        // Check if the app is in the background
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.detached) {
          await _database!.close();
        }
      }
    }
  }

  Future<Database> _initDatabase() async {
    // Check the platform
    if (Platform.isWindows || Platform.isLinux) {
      databaseFactory = databaseFactoryFfi;
    }
    String databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'attendify.db');

    return await openDatabase(
      path,
      version: 2, // Increment the version to trigger the onUpgrade callback
      onCreate: (Database db, int version) async {
        await db.execute('''
        CREATE TABLE students(
          subjectCode TEXT,
          name TEXT,
          status TEXT,
          firstQuarterGrade TEXT,
          secondQuarterGrade TEXT,
          thirdQuarterGrade TEXT,
          fourthQuarterGrade TEXT
        )
      ''');

        await db.execute('''
        CREATE TABLE attendance(
          subjectCode TEXT,
          studentName TEXT,
          status TEXT,
          date TEXT
        )
      ''');

        await db.execute('''
        CREATE TABLE users(
          username TEXT,
          password TEXT,
          role TEXT
        )
      ''');

        await db.execute('''
    CREATE TABLE teachers(
      subjectCode TEXT,
      name TEXT
    )
  ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion == 1 && newVersion == 2) {
          // Add the "role" column to the "users" table
          await db.execute('ALTER TABLE users ADD COLUMN role TEXT');
        }
      },
    );
  }
}

class GradeScreen extends StatefulWidget {
  final String subjectCode;
  final String role;
  final String teacherUsername;
  final DatabaseHelper databaseHelper;

  const GradeScreen(
    this.subjectCode,
    this.role, {
    super.key,
    required this.teacherUsername,
    required this.databaseHelper,
  });

  @override
  GradeScreenState createState() => GradeScreenState();
}

class GradeScreenState extends State<GradeScreen> {
  List<Student> students = [];
  List<Student> filteredStudents = [];
  List<AttendanceRecord> attendanceRecords = [];

  bool _canEditStatus = false;

  final TextEditingController _searchController = TextEditingController();
  late final DatabaseHelper _databaseHelper;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.subjectCode,
            style: const TextStyle(color: Color(0xffBEA18E)),
          ),
          backgroundColor: const Color(0xFF45191C),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await loadData();
          },
          child: Column(
            children: [
              if (students.isNotEmpty) _buildSearchField(),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredStudents.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.0),
                        color: const Color(0xFF826B5D),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _showStudentNamePopup(
                                    context, filteredStudents[index].name);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10.0),
                                  color: const Color(0xffBEA18E),
                                ),
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  filteredStudents[index].name,
                                  style: const TextStyle(fontSize: 12.0),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Color(0xFFBEA18E),
                            ),
                            onPressed: () {
                              _showGradePopup(context, index);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ));
  }

  @override
  void initState() {
    super.initState();
    _databaseHelper = widget.databaseHelper;
    loadData();
  }

  Future<bool> isTeachingSubject(String subjectCode) async {
    final List<Teacher> teachers =
        await _databaseHelper.getTeachers(subjectCode);

    // Check if the teacher's username matches any teacher for the subject
    return teachers.any((teacher) =>
        teacher.name.toLowerCase() == widget.teacherUsername.toLowerCase());
  }

  loadData() async {
    await _databaseHelper.createAttendanceTable();
    students = await _databaseHelper.getStudents(widget.subjectCode);
    attendanceRecords =
        await _databaseHelper.getAttendanceRecords(widget.subjectCode);

    // Determine user role and set _canEditStatus
    _canEditStatus =
        widget.role == 'Teacher' && await isTeachingSubject(widget.subjectCode);

    // Only update filteredStudents if there are existing students
    if (students.isNotEmpty) {
      filteredStudents = List.from(students);
    }

    setState(() {});
  }

  saveData() async {
    await _databaseHelper.deleteAllStudents(widget.subjectCode);

    for (var student in students) {
      await _databaseHelper.insertStudent(student, widget.subjectCode);
    }
  }

  Widget _buildGradeInput(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16.0,
              color: Color(0xFF45191C),
            ),
          ),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            readOnly: !_canEditStatus,
            decoration: const InputDecoration(
              labelText: 'Grade',
              filled: true,
              fillColor: Color(0xffBEA18E),
            ),
          ),
          const SizedBox(height: 16.0),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        onChanged: (query) {
          _filterStudents(query);
        },
        decoration: const InputDecoration(
          labelText: 'Search',
          filled: true,
          fillColor: Color(0xffBEA18E),
          suffixIcon: Icon(
            Icons.search,
            color: Color(0xFF45191C),
          ),
        ),
      ),
    );
  }

  void _filterStudents(String query) {
    setState(() {
      if (query.isEmpty) {
        // If the query is empty, show all students
        filteredStudents = List.from(students);
      } else {
        // Filter students based on the search query
        filteredStudents = students
            .where((student) =>
                student.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  _showGradePopup(BuildContext context, int studentIndex) {
    TextEditingController firstQuarterGradeController = TextEditingController(
      text: filteredStudents[studentIndex].firstQuarterGrade,
    );
    TextEditingController secondQuarterGradeController = TextEditingController(
      text: filteredStudents[studentIndex].secondQuarterGrade,
    );
    TextEditingController thirdQuarterGradeController = TextEditingController(
      text: filteredStudents[studentIndex].thirdQuarterGrade,
    );
    TextEditingController fourthQuarterGradeController = TextEditingController(
      text: filteredStudents[studentIndex].fourthQuarterGrade,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xffBEA18E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        title: const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'Student Grades',
            style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              color: Color(0xFF45191C),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        content: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
                color: const Color(0xffBEA18E),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Quarter Grades
                  _buildGradeInput(
                    'First Quarter',
                    firstQuarterGradeController,
                  ),
                  _buildGradeInput(
                    'Second Quarter',
                    secondQuarterGradeController,
                  ),
                  _buildGradeInput(
                    'Third Quarter',
                    thirdQuarterGradeController,
                  ),
                  _buildGradeInput(
                    'Fourth Quarter',
                    fourthQuarterGradeController,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text(
              !_canEditStatus ? 'Close' : 'Cancel',
              style: const TextStyle(
                color: Color(0xFF45191C),
              ),
            ),
          ),
          if (_canEditStatus)
            TextButton(
              onPressed: () async {
                String newFirstQuarterGrade =
                    firstQuarterGradeController.text.trim();
                String newSecondQuarterGrade =
                    secondQuarterGradeController.text.trim();
                String newThirdQuarterGrade =
                    thirdQuarterGradeController.text.trim();
                String newFourthQuarterGrade =
                    fourthQuarterGradeController.text.trim();

                setState(() {
                  // Update the student's grades
                  filteredStudents[studentIndex].firstQuarterGrade =
                      newFirstQuarterGrade;
                  filteredStudents[studentIndex].secondQuarterGrade =
                      newSecondQuarterGrade;
                  filteredStudents[studentIndex].thirdQuarterGrade =
                      newThirdQuarterGrade;
                  filteredStudents[studentIndex].fourthQuarterGrade =
                      newFourthQuarterGrade;

                  // Save the changes to the database
                  saveData();
                });
                Navigator.pop(context);
              },
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Color(0xFF45191C),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Function to show the student name popup
  void _showStudentNamePopup(BuildContext context, String fullName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xffBEA18E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
          title: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info, color: Color(0xFF45191C)),
              SizedBox(width: 8.0),
              Text(
                'Student Name',
                style: TextStyle(
                  fontSize: 20.0,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF45191C),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(
                fullName,
                style: const TextStyle(fontSize: 20.0),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Color(0xFF45191C),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginUsernameController =
      TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();
  final TextEditingController _registerUsernameController =
      TextEditingController();
  final TextEditingController _registerPasswordController =
      TextEditingController();
  late String _loginSelectedRole;
  late String _registrationSelectedRole;
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF45191C),
      body: SingleChildScrollView(
        child: Stack(
          children: [
            // Background for the login screen
            Container(
              color: const Color(0xFF45191C),
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),
                  const ListTile(
                    title: Center(
                      child: Text(
                        'Attendify',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF826B5D),
                        ),
                      ),
                    ),
                  ),
                  Image.asset(
                    'assets/logo.png',
                    width: 200,
                    height: 350,
                  ),
                  ElevatedButton(
                    onPressed: () {
                      _showLoginDialog(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xffBEA18E),
                    ),
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: Color(0xFF45191C),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      _showRegistrationDialog(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xffBEA18E),
                    ),
                    child: const Text(
                      'Register',
                      style: TextStyle(
                        color: Color(0xFF45191C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Close the database when the widget is disposed
    _databaseHelper._closeDatabase();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loginSelectedRole = 'Regular Student';
    _registrationSelectedRole = 'Regular Student';
    if (Platform.isAndroid || Platform.isIOS) _requestPermissions();
  }

  bool _isPasswordComplex(String password) {
    // Password should contain at least one lowercase letter, one uppercase letter, and one number
    final RegExp passwordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$');
    return passwordRegex.hasMatch(password);
  }

  Future<void> _requestPermissions() async {
    final PermissionStatus status = await Permission.storage
        .request(); // Use Permission.storage for write external storage

    if (status != PermissionStatus.granted) {
      // Handle permission denied or show a message to the user
    }
  }

  void _resetRegistrationDialog() {
    _registerUsernameController.clear();
    _registerPasswordController.clear();
    _registrationSelectedRole = 'Regular Student';
  }

  Future<void> _showErrorDialog(
      BuildContext context, String errorMessage) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF826B5D),
          title: const Text(
            'Error',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF45191C),
            ),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  errorMessage,
                  style: const TextStyle(
                    color: Color(0xFF45191C),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBEA18E),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFF45191C),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  _showLoginDialog(BuildContext context) {
    bool obscurePassword = true;
    String errorMessage = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF826B5D),
            content: SingleChildScrollView(
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Center(
                        child: Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF45191C),
                          ),
                        ),
                      ),
                    ),
                    TextField(
                      controller: _loginUsernameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        filled: true,
                        fillColor: const Color(0xffBEA18E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.black, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.black, width: 1.0),
                        ),
                        labelStyle: const TextStyle(color: Colors.black),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _loginPasswordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        filled: true,
                        fillColor: const Color(0xffBEA18E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.black, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.black, width: 1.0),
                        ),
                        labelStyle: const TextStyle(color: Colors.black),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: const Color(0xFF45191C),
                          ),
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffBEA18E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        dropdownColor: const Color(0xffBEA18E),
                        value: _loginSelectedRole,
                        items: [
                          'Regular Student',
                          'Irregular Student',
                          'Teacher'
                        ].map((String role) {
                          return DropdownMenuItem<String>(
                            value: role,
                            child: Text(
                              role,
                              style: const TextStyle(
                                color: Color(0xFF45191C),
                                fontSize: 16,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _loginSelectedRole = newValue;
                              errorMessage = '';
                            });
                          }
                        },
                        // Set underline to an empty SizedBox to remove the underline
                        underline: const SizedBox(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xffBEA18E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF45191C),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(), // Pushes the Login button to the right
                  TextButton(
                    onPressed: () async {
                      String username = _loginUsernameController.text.trim();
                      String password = _loginPasswordController.text.trim();

                      // Check for empty fields
                      if (username.isEmpty || password.isEmpty) {
                        setState(() {
                          errorMessage = 'Username and password are required.';
                          _showErrorDialog(context, errorMessage);
                        });
                        return;
                      }
                      String? userRole = await _databaseHelper.validateUser(
                        username,
                        password,
                        _loginSelectedRole,
                      );

                      if (userRole != null) {
                        if (!context.mounted) return;
                        Navigator.pop(context);

                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SubjectList(
                              role: userRole,
                              teacherUsername: username,
                              databaseHelper: _databaseHelper,
                            ),
                          ),
                        );
                      } else {
                        setState(() {
                          errorMessage = 'Invalid username or password';
                          _showErrorDialog(context, errorMessage);
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xffBEA18E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: Color(0xFF45191C),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  _showRegistrationDialog(BuildContext context) async {
    bool obscurePassword = true;
    List<String> subjects = [
      'IM211',
      'CC214',
      'NET212',
      'GE105',
      'GE106',
      'GENSOC',
      'PE3',
      'ITELECTV'
    ];

    List<String> availableSubjects =
        await _databaseHelper.getAvailableSubjects();

    Map<String, bool> selectedSubjects = {};
    for (String subject in subjects) {
      selectedSubjects[subject] = false;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF826B5D),
            content: SingleChildScrollView(
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Center(
                        child: Text(
                          'Register',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF45191C),
                          ),
                        ),
                      ),
                    ),
                    TextField(
                      controller: _registerUsernameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        filled: true,
                        fillColor: const Color(0xffBEA18E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.black, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.black, width: 1.0),
                        ),
                        labelStyle: const TextStyle(color: Colors.black),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _registerPasswordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        filled: true,
                        fillColor: const Color(0xffBEA18E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.black, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.black, width: 1.0),
                        ),
                        labelStyle: const TextStyle(color: Colors.black),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: const Color(0xFF45191C),
                          ),
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.all(8),
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xffBEA18E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        dropdownColor: const Color(0xffBEA18E),
                        value: _registrationSelectedRole,
                        items: [
                          'Irregular Student',
                          'Regular Student',
                          'Teacher'
                        ].map((String role) {
                          return DropdownMenuItem<String>(
                            value: role,
                            child: Text(
                              role,
                              style: const TextStyle(
                                color: Color(0xFF45191C),
                                fontSize: 16,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _registrationSelectedRole = newValue;
                            });
                          }
                        },
                        // Set underline to an empty SizedBox to remove the underline
                        underline: const SizedBox(),
                      ),
                    ),
                    if (_registrationSelectedRole == 'Irregular Student') ...[
                      Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xffBEA18E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Select Subject/s:',
                            style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF45191C),
                            ),
                          )),
                      for (String subject in subjects)
                        RoundedCheckbox(
                          label: subject,
                          value: selectedSubjects[subject]!,
                          onChanged: (bool? value) {
                            setState(() {
                              selectedSubjects[subject] = value!;
                            });
                          },
                        ),
                    ],
                    if (_registrationSelectedRole == 'Teacher') ...[
                      Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xffBEA18E),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Select Teaching Subject/s:',
                            style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF45191C),
                            ),
                          )),
                      for (String subject in availableSubjects)
                        RoundedCheckbox(
                          label: subject,
                          value: selectedSubjects[subject]!,
                          onChanged: (bool? value) {
                            setState(() {
                              selectedSubjects[subject] = value!;
                            });
                          },
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ElevatedButton(
                        onPressed: () async {
                          String username =
                              _registerUsernameController.text.trim();
                          String password =
                              _registerPasswordController.text.trim();

                          if (username.isNotEmpty && password.isNotEmpty) {
                            // Password complexity check
                            if (!_isPasswordComplex(password)) {
                              _showErrorDialog(
                                context,
                                'Password must contain at least one lowercase letter, one uppercase letter, and one number.',
                              );
                              return; // Prevent registration if password is not complex enough
                            }
                            if (password.length < 6) {
                              _showErrorDialog(
                                context,
                                'Password must be at least 6 characters long.',
                              );
                              return; // Prevent registration if password is too short
                            }
                            if ((_registrationSelectedRole ==
                                        'Irregular Student' ||
                                    _registrationSelectedRole == 'Teacher') &&
                                !selectedSubjects.containsValue(true)) {
                              _showErrorDialog(context,
                                  'Please select at least one subject.');
                              return; // Prevent registration if no subject is selected
                            }
                            bool isUsernameTaken =
                                await _databaseHelper.isUsernameTaken(username);

                            if (!isUsernameTaken) {
                              await _databaseHelper.insertUser(username,
                                  password, _registrationSelectedRole);

                              if (_registrationSelectedRole ==
                                  'Irregular Student') {
                                for (String subject in subjects) {
                                  if (selectedSubjects[subject]!) {
                                    await _databaseHelper.insertStudent(
                                      Student(name: username),
                                      subject,
                                    );
                                  }
                                }
                              } else if (_registrationSelectedRole ==
                                  'Regular Student') {
                                for (String subject in subjects) {
                                  await _databaseHelper.insertStudent(
                                    Student(name: username),
                                    subject,
                                  );
                                }
                              } else if (_registrationSelectedRole ==
                                  'Teacher') {
                                for (String subject in availableSubjects) {
                                  if (selectedSubjects[subject]!) {
                                    await _databaseHelper.insertTeacher(
                                      Teacher(name: username),
                                      subject,
                                    );
                                  }
                                }
                              }

                              _resetRegistrationDialog();
                              if (!context.mounted) return;
                              Navigator.pop(context);
                            } else {
                              if (!context.mounted) return;
                              _showErrorDialog(
                                context,
                                'Username is already taken.',
                              );
                            }
                          } else {
                            _showErrorDialog(
                              context,
                              'Username and password are required.',
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFBEA18E),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Register',
                            style: TextStyle(
                              color: Color(0xFF45191C),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendify',
      home: const LoginScreen(),
      theme: ThemeData(
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF45191C),
          iconTheme: IconThemeData(color: Color(0xffBEA18E)),
          centerTitle: true,
        ),
        scaffoldBackgroundColor: const Color(0xFF826B5D),
      ),
    );
  }
}

class RoundedCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const RoundedCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xffBEA18E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CheckboxListTile(
          title: Text(label),
          tileColor: const Color(0xffBEA18E),
          value: value,
          onChanged: onChanged,
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ),
    );
  }
}

class Student {
  String name;
  String status;
  String firstQuarterGrade;
  String secondQuarterGrade;
  String thirdQuarterGrade;
  String fourthQuarterGrade;

  Student({
    required this.name,
    this.status = '',
    this.firstQuarterGrade = '0.0',
    this.secondQuarterGrade = '0.0',
    this.thirdQuarterGrade = '0.0',
    this.fourthQuarterGrade = '0.0',
  });
  Map<String, dynamic> toMap(String subjectCode) {
    return {
      'subjectCode': subjectCode,
      'name': name,
      'status': status,
      'firstQuarterGrade': firstQuarterGrade,
      'secondQuarterGrade': secondQuarterGrade,
      'thirdQuarterGrade': thirdQuarterGrade,
      'fourthQuarterGrade': fourthQuarterGrade,
    };
  }
}

class SubjectList extends StatelessWidget {
  final String role;
  final String teacherUsername;
  final DatabaseHelper databaseHelper;

  const SubjectList(
      {super.key,
      required this.role,
      required this.teacherUsername,
      required this.databaseHelper});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Attendify',
          style: TextStyle(color: Color(0xffBEA18E)),
        ),
        actions: [
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            onSelected: (value) {
              if (value == 'logout') {
                _showLogoutDialog(context);
              } else if (value == 'deleteAccount') {
                _showDeleteAccountDialog(context);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(
                  leading: Icon(
                    Icons.logout,
                    color: Color(0xFF45191C),
                  ),
                  title: Text(
                    'Logout',
                    style: TextStyle(
                      color: Color(0xFF45191C),
                    ),
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'deleteAccount',
                child: ListTile(
                  leading: Icon(
                    Icons.delete,
                    color: Color(0xFF45191C),
                  ),
                  title: Text(
                    'Delete Account',
                    style: TextStyle(
                      color: Color(0xFF45191C),
                    ),
                  ),
                ),
              ),
            ],
            // Set the background color for the dropdown
            color: const Color(0xffBEA18E),
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
        children: [
          SubjectTile(
            'IM211',
            role: role,
            teacherUsername: teacherUsername,
            databaseHelper: databaseHelper,
          ),
          SubjectTile(
            'CC214',
            role: role,
            teacherUsername: teacherUsername,
            databaseHelper: databaseHelper,
          ),
          SubjectTile(
            'NET212',
            role: role,
            teacherUsername: teacherUsername,
            databaseHelper: databaseHelper,
          ),
          SubjectTile(
            'GE105',
            role: role,
            teacherUsername: teacherUsername,
            databaseHelper: databaseHelper,
          ),
          SubjectTile(
            'GE106',
            role: role,
            teacherUsername: teacherUsername,
            databaseHelper: databaseHelper,
          ),
          SubjectTile(
            'GENSOC',
            role: role,
            teacherUsername: teacherUsername,
            databaseHelper: databaseHelper,
          ),
          SubjectTile(
            'PE3',
            role: role,
            teacherUsername: teacherUsername,
            databaseHelper: databaseHelper,
          ),
          SubjectTile(
            'ITELECTV',
            role: role,
            teacherUsername: teacherUsername,
            databaseHelper: databaseHelper,
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xffBEA18E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        title: const Text(
          'Confirmation',
          style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              color: Color(0xFF45191C)),
        ),
        content: const Text('Are you sure you want to delete your account?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text(
              'No',
              style: TextStyle(
                color: Color(0xFF45191C),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (role == 'Teacher') {
                // Use the deleteTeacher method to delete the teacher's account
                await databaseHelper.deleteTeacher(teacherUsername);
              } else if (role == 'Regular Student' ||
                  role == "Irregular Student") {
                await databaseHelper.deleteStudent(teacherUsername, role);
              }
              // Navigate to the login screen
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
            child: const Text(
              'Yes',
              style: TextStyle(
                color: Color(0xFF45191C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xffBEA18E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              color: Color(0xFF45191C)),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text(
              'No',
              style: TextStyle(
                color: Color(0xFF45191C),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
            child: const Text(
              'Yes',
              style: TextStyle(
                color: Color(0xFF45191C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SubjectTile extends StatelessWidget {
  final String subjectCode;
  final String role;
  final String teacherUsername;
  final DatabaseHelper databaseHelper;

  const SubjectTile(
    this.subjectCode, {
    super.key,
    required this.role,
    required this.teacherUsername,
    required this.databaseHelper,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(10.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: InkWell(
        onTap: () {
          _showOptionsDialog(context);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.0),
            color: const Color(0xffBEA18E),
          ),
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  subjectCode,
                  style: const TextStyle(fontSize: 18.0),
                ),
                const SizedBox(height: 8.0),
                FutureBuilder<List<Teacher>>(
                  future: databaseHelper.getTeachers(subjectCode),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text('Teacher: None');
                    } else {
                      // Display the teacher's name
                      return Text('Teacher: ${snapshot.data![0].name}');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xffBEA18E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        title: const Text(
          'Select Option',
          style: TextStyle(
            fontSize: 20.0,
            fontWeight: FontWeight.bold,
            color: Color(0xFF45191C),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Attendance'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AttendanceScreen(
                      subjectCode,
                      role,
                      teacherUsername: teacherUsername,
                      databaseHelper: databaseHelper,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              title: const Text('Grade'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GradeScreen(
                      subjectCode,
                      databaseHelper: databaseHelper,
                      role,
                      teacherUsername: teacherUsername,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class Teacher {
  String name;

  Teacher({required this.name});

  Map<String, dynamic> toMap(String subjectCode) {
    return {
      'subjectCode': subjectCode,
      'name': name,
    };
  }
}
