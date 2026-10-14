# School Management System - Attendance & Analytics Module
## System Requirements & Architecture Document

---

## Step 1: System Logic & Architecture

### User Roles Defined

| Role | Key Permissions |
|------|-----------------|
| **Admin** | Approve attendance unlock requests, view all reports, manage linked siblings, override locks, audit log access |
| **Class Teacher** | Take attendance (10:15-11:10 AM), view class demographics, request attendance modifications, view weekly reports |
| **Subject Teacher** | Real-time mid-day status updates during 5th period, view today's attendance, mark student status changes |
| **Guardian** | View linked siblings' data, request sibling linking, receive notifications for absences/departures |
| **Student** | View own attendance and results (future scope for student-facing app) |

### Core Data Models (Extended Schema)

```sql
-- attendance_requests: For modification requests after lock time
CREATE TABLE attendance_requests (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  class_id INT NOT NULL,
  date DATE NOT NULL,
  original_status ENUM('present','absent','late','leave') NOT NULL,
  requested_status ENUM('present','absent','late','leave') NOT NULL,
  reason TEXT NOT NULL,
  status ENUM('pending','approved','rejected') DEFAULT 'pending',
  requested_by INT NOT NULL,
  decided_by INT,
  decided_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_student_date (student_id, date),
  CONSTRAINT fk_req_student FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
  CONSTRAINT fk_req_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  CONSTRAINT fk_req_requested_by FOREIGN KEY (requested_by) REFERENCES users(id) ON DELETE CASCADE
);

-- mid_day_status: Real-time tracking for 5th period/substitute teachers
CREATE TABLE mid_day_status (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  date DATE NOT NULL,
  status ENUM('normal','ran_away','on_leave','early_departure') DEFAULT 'normal',
  marked_by INT NOT NULL,
  marked_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  notes VARCHAR(255),
  UNIQUE KEY uq_midday (student_id, date),
  CONSTRAINT fk_midday_student FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
);

-- linked_siblings: Guardian-sibling relationships (many-to-many)
CREATE TABLE linked_siblings (
  id INT AUTO_INCREMENT PRIMARY KEY,
  guardian_id INT NOT NULL,
  student_id INT NOT NULL,
  status ENUM('pending','approved','rejected') DEFAULT 'pending',
  requested_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  decided_by INT,
  decided_at DATETIME,
  UNIQUE KEY uq_guardian_student (guardian_id, student_id),
  CONSTRAINT fk_sibling_guardian FOREIGN KEY (guardian_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_sibling_student FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
);

-- attendance_audit_log: Admin actions for compliance
CREATE TABLE attendance_audit_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  admin_id INT NOT NULL,
  action_type ENUM('unlock_attendance','approve_request','reject_request','override_status') NOT NULL,
  target_student_id INT,
  target_date DATE,
  original_value VARCHAR(50),
  new_value VARCHAR(50),
  reason TEXT,
  ip_address VARCHAR(45),
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## Step 2: Practical Human-Centered Additions & Edge Cases

### 2.1 Late Arrival Handling
```javascript
// In attendance marking logic
const CLASS_START_TIME = '10:15:00';
const LATE_CUTOFF = '11:10:00';

function determineAttendanceStatus(entryTime, isClassTeacher) {
  // Class Teacher taking attendance (10:15 - 11:10)
  if (isClassTeacher && entryTime <= LATE_CUTOFF) {
    return { status: 'present', isLate: false };
  }

  // Late arrival logic
  if (entryTime > CLASS_START_TIME) {
    // Check if already marked absent by class teacher
    return { status: 'late', isLate: true, badge: '🚶 Late' };
  }

  // After 11:10 - already locked
  return null;
}
```

### 2.2 SMS/Push Notification Triggers
```javascript
// Notification rules
const NOTIFICATION_TRIGGERS = {
  ABSENT: {
    sms: true,
    push: true,
    template: 'Your child {name} was marked ABSENT on {date} at {school_name}.',
    priority: 'high'
  },
  RAN_AWAY: {
    sms: true,
    push: true,
    template: 'URGENT: Your child {name} marked as LEFT WITHOUT PERMISSION on {date}. Please contact school immediately.',
    priority: 'critical'
  },
  EARLY_DEPARTURE: {
    sms: true,
    push: true,
    template: 'Your child {name} left school early on {date}. Reason: {notes}',
    priority: 'high'
  }
};
```

### 2.3 Holiday/Exam Day Exception Logic
```javascript
function isAttendanceLocked(classId, date) {
  // Check if date is a holiday
  const isHoliday = await db.query(
    'SELECT 1 FROM holidays WHERE date = ?', [date]
  );

  // Check if it's an exam day (no regular attendance)
  const isExamDay = await db.query(
    'SELECT 1 FROM exam_events e JOIN exams ex ON e.id = ex.event_id ' +
    'WHERE e.start_date = ? AND ex.class_id = ?', [date, classId]
  );

  // Check session status
  const session = await db.query(
    'SELECT is_active FROM sessions s JOIN classes c ON c.session_id = s.id WHERE c.id = ?', [classId]
  );

  // Lock rules
  if (isHoliday || isExamDay || !session.is_active) {
    return { locked: true, reason: 'Holiday/Exam/Inactive Session' };
  }

  // Time-based lock
  const now = new Date();
  const lockTime = new Date(date + 'T11:10:00');

  return {
    locked: now > lockTime,
    reason: now > lockTime ? 'Attendance window closed' : null
  };
}
```

### 2.4 Weekly PDF Report Generation
```javascript
async function generateWeeklyAttendancePDF(teacherId, weekStartDate) {
  const students = await getClassStudents(teacherId);
  const attendanceData = await getWeeklyAttendance(students, weekStartDate);

  const pdf = new PDFDocument();
  pdf.fontSize(18).text('Weekly Attendance Report', { align: 'center' });
  pdf.moveDown();

  // Summary table
  const tableData = students.map(s => ({
    name: s.name,
    roll: s.roll,
    present: attendanceData[s.id].present,
    absent: attendanceData[s.id].absent,
    late: attendanceData[s.id].late,
    percentage: attendanceData[s.id].percentage
  }));

  // Render table...
  pdf.save();
  return pdf;
}
```

---

## Step 3: Feature Breakdown & Database Schemas

### Feature 3.1: Attendance Rules & Time-Locks

**Backend API Requirements:**
```javascript
// POST /api/teacher/attendance/take
// PUT /api/teacher/attendance/update
// POST /api/teacher/attendance/request-unlock

router.post('/attendance/take', auth, async (req, res) => {
  const { class_id, date, attendance } = req.body; // attendance: [{student_id, status, late_minutes?}]

  // Check time lock
  const lockStatus = await checkAttendanceLock(class_id, date);
  if (lockStatus.locked && !req.user.hasAdminOverride) {
    return res.status(403).json({
      error: 'ATTENDANCE_LOCKED',
      message: 'Attendance window closed. Request unlock from Admin.',
      lock_time: '11:10 AM',
      unlock_request_endpoint: '/api/teacher/attendance/request-unlock'
    });
  }

  // Process attendance...
});

// POST /api/teacher/attendance/request-unlock
router.post('/attendance/request-unlock', auth, async (req, res) => {
  const { student_id, date, reason, requested_status } = req.body;

  // Create attendance request
  const [result] = await db.query(
    `INSERT INTO attendance_requests
     (student_id, class_id, date, requested_status, reason, requested_by)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [student_id, class_id, date, requested_status, reason, req.user.id]
  );

  // Notify admin
  await sendAdminNotification('ATTENDANCE_UNLOCK_REQUEST', {
    student_id, date, reason, request_id: result.insertId
  });

  return res.status(201).json({ request_id: result.insertId, status: 'pending' });
});
```

**Frontend UX Flow:**
```
1. Teacher opens "Take Attendance" screen
2. System shows: "Morning Attendance - Class 9 Science" (10:15-11:10)
3. Teacher marks students (Present/Absent/Late/Leave)
4. After 11:10 AM - Screen shows "Attendance Locked"
5. Teacher sees "Request Edit" button next to each student
6. Form: Select new status, enter reason, submit
7. Admin gets notification, approves/rejects
8. Teacher notified of decision, can edit if approved
```

### Feature 3.2: 5th Period / Substitute Teacher Real-Time Tracking

**Backend API:**
```javascript
// GET /api/teacher/midday-status?class_id=X&date=YYYY-MM-DD
// POST /api/teacher/midday-status

router.get('/midday-status', auth, async (req, res) => {
  const { class_id, date } = req.query;

  // Verify teacher has access to this class (5th period or substitute)
  const hasAccess = await verifyPeriodAccess(req.user.id, class_id, 5);
  if (!hasAccess) {
    return res.status(403).json({ error: 'NO_PERIOD_ACCESS' });
  }

  const [students] = await db.query(
    `SELECT s.id, s.name, s.roll, s.photo,
            COALESCE(m.status, 'normal') as mid_day_status,
            m.marked_at, m.notes, m.marked_by
     FROM students s
     LEFT JOIN mid_day_status m ON s.id = m.student_id AND m.date = ?
     WHERE s.class_id = ? AND s.status = 'active'`,
    [date || today, class_id]
  );

  return res.json({ students });
});

router.post('/midday-status', auth, async (req, res) => {
  const { student_id, status, notes } = req.body;

  // Only allow specific statuses
  const VALID_STATUSES = ['normal', 'ran_away', 'on_leave', 'early_departure'];
  if (!VALID_STATUSES.includes(status)) {
    return res.status(400).json({ error: 'INVALID_STATUS' });
  }

  await db.query(
    `INSERT INTO mid_day_status (student_id, date, status, marked_by, notes)
     VALUES (?, CURDATE(), ?, ?, ?)
     ON DUPLICATE UPDATE status = ?, marked_by = ?, marked_at = NOW(), notes = ?`,
    [student_id, status, req.user.id, notes, status, req.user.id, notes]
  );

  // Trigger notifications for critical statuses
  if (status === 'ran_away' || status === 'early_departure') {
    await notifyGuardianUrgent(student_id, status, notes);
  }

  return res.json({ success: true, status });
});
```

**Frontend UX Flow:**
```
1. Teacher opens 5th Period screen
2. Sees "Mid-Day Attendance Tracking" card
3. List of students with real-time status badges:
   🟢 Normal (green badge)
   🟡 Ran Away / Left Without Permission (red warning badge)
   🔵 On Leave (blue badge)
   🟣 Early Departure (purple badge)
4. Teacher taps student → Can update status
5. Status changes reflect instantly for all viewing teachers
6. Guardian receives immediate SMS for "Ran Away" status
```

### Feature 3.3: Student Analytics & Academic History

**Backend API:**
```javascript
// GET /api/student/:id/attendance-history?session=2026
router.get('/student/:id/attendance-history', auth, async (req, res) => {
  const { id } = req.params;
  const { session } = req.query;

  // Monthly breakdown
  const monthlyStats = await db.query(
    `SELECT
       MONTH(date) as month,
       SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) as present,
       SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END) as absent,
       SUM(CASE WHEN status = 'late' THEN 1 ELSE 0 END) as late,
       SUM(CASE WHEN status = 'leave' THEN 1 ELSE 0 END) as leave,
       COUNT(*) as total_days
     FROM attendance
     WHERE student_id = ? AND YEAR(date) = ?
     GROUP BY MONTH(date)
     ORDER BY month`,
    [id, session || currentYear]
  );

  // Annual summary
  const annualStats = await db.query(
    `SELECT
       COUNT(*) as total_school_days,
       SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) as total_present,
       SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END) as total_absent,
       SUM(CASE WHEN status = 'late' THEN 1 ELSE 0 END) as total_late,
       SUM(CASE WHEN status = 'leave' THEN 1 ELSE 0 END) as total_leave
     FROM attendance
     WHERE student_id = ? AND YEAR(date) = ?`,
    [id, session || currentYear]
  );

  const annual = annualStats[0];
  const attendancePercentage = ((annual.total_present / annual.total_school_days) * 100).toFixed(2);

  return res.json({
    session,
    annual: {
      ...annual,
      attendance_percentage: attendancePercentage,
      total_days: annual.total_school_days
    },
    monthly: monthlyStats
  });
});
```

### Feature 3.4: Dashboard Statistics & Class Demographics

**Backend API:**
```javascript
// GET /api/teacher/class-demographics?class_id=X
router.get('/class-demographics', auth, async (req, res) => {
  const { class_id } = req.query;

  const demographics = await db.query(
    `SELECT
       COUNT(*) as total_students,
       SUM(CASE WHEN gender = 'Male' THEN 1 ELSE 0 END) as male_count,
       SUM(CASE WHEN gender = 'Female' THEN 1 ELSE 0 END) as female_count,
       SUM(CASE WHEN gender = 'Other' THEN 1 ELSE 0 END) as other_count,
       SUM(CASE WHEN religion = 'Islam' THEN 1 ELSE 0 END) as islam_count,
       SUM(CASE WHEN religion = 'Hinduism' THEN 1 ELSE 0 END) as hinduism_count,
       SUM(CASE WHEN religion = 'Christianity' THEN 1 ELSE 0 END) as christianity_count,
       SUM(CASE WHEN religion = 'Buddhism' THEN 1 ELSE 0 END) as buddhism_count,
       SUM(CASE WHEN religion IN ('Other', '') OR religion IS NULL THEN 1 ELSE 0 END) as other_religion_count
     FROM students
     WHERE class_id = ? AND status = 'active'`,
    [class_id]
  );

  return res.json(demographics[0]);
});

// GET /api/student/:id/profile
router.get('/student/:id/profile', auth, async (req, res) => {
  const { id } = req.params;

  const student = await db.query(
    `SELECT s.*, c.name as class_name, c.section, c.group_name,
            g.name as guardian_name, g.phone as guardian_phone,
            g.email as guardian_email
     FROM students s
     JOIN classes c ON s.class_id = c.id
     LEFT JOIN users g ON s.guardian_id = g.id
     WHERE s.id = ?`,
    [id]
  );

  return res.json(student[0]);
});
```

### Feature 3.5: Multi-Sibling Guardian Portal

**Backend API:**
```javascript
// POST /api/guardian/request-sibling-link
router.post('/request-sibling-link', auth, async (req, res) => {
  const { student_id, guardian_id } = req.body; // student_id to link to guardian

  // Check if student already has a guardian linked
  const existingGuardian = await db.query(
    `SELECT guardian_id FROM students WHERE id = ?`, [student_id]
  );

  if (existingGuardian[0]?.guardian_id) {
    return res.status(400).json({
      error: 'STUDENT_ALREADY_LINKED',
      message: 'Student already has a guardian. Contact admin to change.'
    });
  }

  await db.query(
    `INSERT INTO linked_siblings (guardian_id, student_id, status)
     VALUES (?, ?, 'pending')`,
    [guardian_id, student_id]
  );

  return res.status(201).json({ status: 'pending', message: 'Link request submitted' });
});

// GET /api/guardian/dashboard
router.get('/dashboard', auth, async (req, res) => {
  const guardianId = req.user.id;

  const linkedStudents = await db.query(
    `SELECT s.*, c.name as class_name, c.section, c.group_name,
            ls.status as link_status
     FROM linked_siblings ls
     JOIN students s ON ls.student_id = s.id
     JOIN classes c ON s.class_id = c.id
     WHERE ls.guardian_id = ? AND ls.status = 'approved'`,
    [guardianId]
  );

  // Get all data for each sibling
  const dashboard = await Promise.all(
    linkedStudents.map(async (student) => {
      const [attendance] = await getStudentAttendanceSummary(student.id);
      const [recentResults] = await getRecentResults(student.id, 5);
      return {
        student,
        attendance_summary: attendance[0],
        recent_results: recentResults
      };
    })
  );

  return res.json({
    guardian: req.user,
    siblings: dashboard,
    total_siblings: dashboard.length
  });
});
```

---

## Step 4: UI/UX Flow Specifications

### 4.1 Teacher App - Attendance Screen

```
┌─────────────────────────────────────────┐
│  ← Back          Attendance        ⚙️   │
├─────────────────────────────────────────┤
│  📅 Today, Oct 14, 2026                  │
│  ⏰ 10:45 AM  ·  25 min remaining        │
├─────────────────────────────────────────┤
│  🔵 Class 9 Science · 42 Students        │
├─────────────────────────────────────────┤
│  Search students...                      │
├─────────────────────────────────────────┤
│  ✅ Nosaiba Noha        (1)  📱 📘      │
│     Status: Present ✓                    │
│                                           │
│  ✅ Mohammad Zayed       (2)  📱 📘      │
│     Status: Present ✓                    │
│                                           │
│  ⏸️  Isnat Jaki Enan      (3)  📱 📘      │
│     Status: Late ⏰                      │
│                                           │
│  ❌ Samia Sultana       (4)  📱 📘       │
│     Status: Absent ✗                     │
├─────────────────────────────────────────┤
│  📊 Stats: Present 38 | Late 2 | Absent 2│
├─────────────────────────────────────────┤
│         ✅ Submit Attendance              │
└─────────────────────────────────────────┘
```

### 4.2 Mid-Day Status Screen (5th Period)

```
┌─────────────────────────────────────────┐
│  ← Back      Mid-Day Tracking       📡   │
├─────────────────────────────────────────┐
│  🔵 Class 9 Science · Real-Time          │
│  🟢 Normal: 35  🔴 Ran Away: 2  🔵 Leave:5│
├─────────────────────────────────────────┤
│  🟢 1. Jannatul Mawa (Roll 1)            │
│     ⏰ 10:30 AM                          │
│     [Normal] [Ran Away] [Leave] [Early]  │
│                                           │
│  🔴 2. Isnat Jaki Enan (Roll 2)          │
│     ⚠️ LEFT WITHOUT PERMISSION           │
│     👤 Marked by: Md. Bakthearul         │
│     ⏰ 11:45 AM                          │
│     📞 Emergency Contact: 01819-306747   │
│     [Normal] [Ran Away] [Leave] [Early]  │
│                                           │
│  🔵 3. Samia Sultana (Roll 3)            │
│     🏫 On Authorized Leave               │
│     ⏰ Marked by Class Teacher           │
│     [Normal] [Ran Away] [Leave] [Early]  │
└─────────────────────────────────────────┘
```

### 4.3 Guardian Dashboard - Multi-Sibling View

```
┌─────────────────────────────────────────┐
│  👤 Mr. Mohammad Yaqub           👤 🔔  │
├─────────────────────────────────────────┐
│  👨‍👧‍👦 My Children (2)                      │
├─────────────────────────────────────────┤
│  📱 Toggle View: [All] [Individual]      │
├─────────────────────────────────────────┤
│  ┌───────────────────────────────────┐   │
│  │ 👧 Nosaiba Noha                   │   │
│  │ Class 10 Arts · Roll 1            │   │
│  │ 📊 Attendance: 92% ⬆️  |  ⭐ 3.85 │   │
│  │ ✅ Last present today              │   │
│  └───────────────────────────────────┘   │
│  ┌───────────────────────────────────┐   │
│  │ 👦 Mohammad Zayed                 │   │
│  │ Class 10 Arts · Roll 9            │   │
│  │ 📊 Attendance: 78% ⚠️  |  ⭐ 3.42 │   │
│  │ ⚠️ Absent 5 days this month        │   │
│  └───────────────────────────────────┘   │
├─────────────────────────────────────────┤
│  📈 View Detailed Reports →             │
│  🔗 Request Sibling Link →              │
└─────────────────────────────────────────┘
```

---

## Implementation Priority

| Priority | Feature | Files to Modify |
|----------|---------|-----------------|
| **P0** | Attendance time-lock logic | `backend/routes/teacher.js`, `backend/db.js` |
| **P0** | Mid-day status tracking | New table + API endpoints |
| **P1** | Guardian sibling linking | `backend/routes/guardian.js`, `backend/db.js` |
| **P1** | Demographics dashboard | `backend/routes/admin.js` + Flutter UI |
| **P2** | Weekly PDF reports | `backend/grading.js` + PDFKit |
| **P2** | SMS/Push notifications | `backend/fcm.js` enhancement |

---

## Next Steps for Development

1. **Run Database Migrations**: Execute the new table schemas on both local MySQL and Supabase
2. **Update Backend Routes**: Add the new API endpoints for mid-day tracking and attendance requests
3. **Update Flutter UI**: Implement the new screens for attendance, mid-day tracking, and demographics
4. **Test Edge Cases**: Verify late arrival, holiday, and lock-time behaviors
5. **Deploy to Render**: Push changes and verify on live backend

**Note**: The `ngrok-skip-browser-warning` header is already in place for the Render backend URL (`https://school-management-system-5jqj.onrender.com`).