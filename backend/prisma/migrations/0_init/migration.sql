-- CreateTable users
CREATE TABLE "users" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "role" VARCHAR(20) NOT NULL,
    "username" VARCHAR(50) NOT NULL UNIQUE,
    "password_hash" VARCHAR(255) NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "email" VARCHAR(100),
    "phone" VARCHAR(20),
    "active" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "is_class_teacher" TEXT,
    "designation" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 99,
    "signature" VARCHAR(255),
    "signature_name" VARCHAR(100)
);

-- CreateTable sessions
CREATE TABLE "sessions" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "name" VARCHAR(20) NOT NULL UNIQUE,
    "is_active" INTEGER NOT NULL DEFAULT 0
);

-- CreateTable classes
CREATE TABLE "classes" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "name" VARCHAR(50) NOT NULL,
    "section" VARCHAR(20) NOT NULL,
    "group_name" VARCHAR(20),
    "session_id" INTEGER,
    "teacher_id" INTEGER,
    UNIQUE("name", "section")
);
CREATE INDEX "classes_session_id_idx" ON "classes"("session_id");
CREATE INDEX "classes_teacher_id_idx" ON "classes"("teacher_id");

-- CreateTable subjects
CREATE TABLE "subjects" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "name" VARCHAR(60) NOT NULL,
    "class_id" INTEGER NOT NULL,
    "teacher_id" INTEGER,
    "full_marks" INTEGER NOT NULL DEFAULT 100,
    "group_name" VARCHAR(20) NOT NULL DEFAULT 'Compulsory',
    "is_optional" INTEGER NOT NULL DEFAULT 0,
    "excluded_from_gpa" INTEGER NOT NULL DEFAULT 0,
    "cq_full" INTEGER,
    "mcq_full" INTEGER,
    "practical_full" INTEGER,
    "subject_code" INTEGER,
    "is_fourth_subject" INTEGER NOT NULL DEFAULT 0,
    "is_elective" INTEGER NOT NULL DEFAULT 0,
    "sort_order" INTEGER,
    "pass_marks" INTEGER,
    "ca_full" INTEGER,
    "written_full" INTEGER,
    UNIQUE("name", "class_id")
);
CREATE INDEX "subjects_class_id_idx" ON "subjects"("class_id");
CREATE INDEX "subjects_teacher_id_idx" ON "subjects"("teacher_id");

-- CreateTable students
CREATE TABLE "students" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_code" VARCHAR(20) NOT NULL UNIQUE,
    "name" VARCHAR(100) NOT NULL,
    "dob" DATE,
    "roll" INTEGER NOT NULL,
    "class_id" INTEGER NOT NULL,
    "guardian_id" INTEGER,
    "guardian_name" VARCHAR(100),
    "guardian_phone" VARCHAR(20),
    "guardian_email" VARCHAR(100),
    "address" VARCHAR(255),
    "photo" VARCHAR(255),
    "father_name" VARCHAR(100),
    "mother_name" VARCHAR(100),
    "birth_cert_no" VARCHAR(50),
    "session_id" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "religion" VARCHAR(30),
    "section" VARCHAR(20),
    "status" VARCHAR(50) DEFAULT 'active',
    "gender" VARCHAR(10),
    "blood_group" VARCHAR(10),
    "optional_subject" VARCHAR(80),
    "phone" VARCHAR(20),
    "email" VARCHAR(100),
    UNIQUE("class_id", "roll")
);
CREATE INDEX "students_guardian_id_idx" ON "students"("guardian_id");

-- CreateTable student_subjects
CREATE TABLE "student_subjects" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER NOT NULL,
    "subject_id" INTEGER NOT NULL,
    "is_mandatory" INTEGER NOT NULL DEFAULT 1,
    "is_fourth_subject" INTEGER NOT NULL DEFAULT 0,
    "is_elective" INTEGER NOT NULL DEFAULT 0,
    "assigned_by" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE("subject_id", "student_id")
);
CREATE INDEX "student_subjects_student_id_idx" ON "student_subjects"("student_id");

-- CreateTable exam_events
CREATE TABLE "exam_events" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "name" VARCHAR(100) NOT NULL,
    "session_id" INTEGER,
    "start_date" DATE,
    "created_by" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "exam_kind" TEXT DEFAULT 'other',
    "year" INTEGER,
    "is_published" INTEGER NOT NULL DEFAULT 0,
    "published_at" TIMESTAMP,
    "promotion_linked" INTEGER NOT NULL DEFAULT 0,
    "notify_guardians" INTEGER NOT NULL DEFAULT 0,
    "notified_at" TIMESTAMP,
    "exam_date" DATE,
    "result_date" DATE
);
CREATE INDEX "exam_events_session_id_idx" ON "exam_events"("session_id");

-- CreateTable exams
CREATE TABLE "exams" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "name" VARCHAR(150) NOT NULL,
    "exam_type" VARCHAR(20) NOT NULL DEFAULT 'class_test',
    "class_id" INTEGER NOT NULL,
    "subject_id" INTEGER NOT NULL,
    "event_id" INTEGER,
    "source" VARCHAR(20) NOT NULL DEFAULT 'teacher',
    "status" VARCHAR(20) NOT NULL DEFAULT 'draft',
    "created_by" INTEGER NOT NULL,
    "exam_date" DATE,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "entry_deadline" TIMESTAMP,
    "entry_open" INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX "exams_class_id_idx" ON "exams"("class_id");
CREATE INDEX "exams_subject_id_idx" ON "exams"("subject_id");
CREATE INDEX "exams_event_id_idx" ON "exams"("event_id");
CREATE INDEX "exams_created_by_idx" ON "exams"("created_by");

-- CreateTable exam_shares
CREATE TABLE "exam_shares" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "exam_id" INTEGER NOT NULL,
    "teacher_id" INTEGER NOT NULL,
    "created_by" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE("exam_id", "teacher_id")
);
CREATE INDEX "exam_shares_teacher_id_idx" ON "exam_shares"("teacher_id");

-- CreateTable marks
CREATE TABLE "marks" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER NOT NULL,
    "exam_id" INTEGER NOT NULL,
    "marks" NUMERIC(5,2) NOT NULL,
    "total" NUMERIC(5,2) NOT NULL DEFAULT 100,
    "comment" VARCHAR(255),
    "cq" NUMERIC(5,2),
    "mcq" NUMERIC(5,2),
    "practical" NUMERIC(5,2),
    "written" NUMERIC(5,2),
    "absent" INTEGER NOT NULL DEFAULT 0,
    "recorded_by" INTEGER,
    "recorded_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "edit_until" TIMESTAMP,
    "ca" NUMERIC(5,2),
    UNIQUE("student_id", "exam_id")
);
CREATE INDEX "marks_exam_id_idx" ON "marks"("exam_id");
CREATE INDEX "marks_recorded_by_idx" ON "marks"("recorded_by");

-- CreateTable ct_marks
CREATE TABLE "ct_marks" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER NOT NULL,
    "subject_id" INTEGER NOT NULL,
    "ct_no" INTEGER NOT NULL DEFAULT 1,
    "marks" NUMERIC(5,2) NOT NULL,
    "full_marks" NUMERIC(5,2) NOT NULL DEFAULT 25,
    "recorded_by" INTEGER,
    "recorded_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "edit_until" TIMESTAMP,
    UNIQUE("ct_no", "student_id", "subject_id")
);
CREATE INDEX "ct_marks_student_id_idx" ON "ct_marks"("student_id");
CREATE INDEX "ct_marks_subject_id_idx" ON "ct_marks"("subject_id");

-- CreateTable attendance
CREATE TABLE "attendance" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER NOT NULL,
    "date" DATE NOT NULL,
    "status" VARCHAR(10) NOT NULL DEFAULT 'present',
    "remark" VARCHAR(255),
    "recorded_by" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "is_escape" INTEGER NOT NULL DEFAULT 0,
    "escape_detected_at" TIMESTAMP,
    "session" VARCHAR(10) NOT NULL DEFAULT 'morning',
    "final_state" VARCHAR(32),
    "leave_ticket_id" INTEGER,
    "override_by" INTEGER,
    "override_reason" VARCHAR(255),
    UNIQUE("student_id", "date", "session")
);
CREATE INDEX "attendance_final_state_idx" ON "attendance"("final_state");
CREATE INDEX "attendance_student_id_date_idx" ON "attendance"("student_id", "date");

-- CreateTable results
CREATE TABLE "results" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER NOT NULL,
    "exam_id" INTEGER NOT NULL,
    "total_gpa_without_4th" NUMERIC(4,2) NOT NULL DEFAULT 0,
    "gpa_4th_bonus" NUMERIC(4,2) NOT NULL DEFAULT 0,
    "final_gpa" NUMERIC(4,2) NOT NULL DEFAULT 0,
    "result_status" VARCHAR(10) NOT NULL DEFAULT 'ABSENT',
    "teacher_remarks" TEXT,
    "computed_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE("student_id", "exam_id")
);
CREATE INDEX "results_exam_id_idx" ON "results"("exam_id");

-- CreateTable notifications
CREATE TABLE "notifications" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER,
    "class_id" INTEGER,
    "title" VARCHAR(150) NOT NULL,
    "body" TEXT NOT NULL,
    "type" VARCHAR(20) NOT NULL DEFAULT 'general',
    "target_type" VARCHAR(20) NOT NULL DEFAULT 'all',
    "related_id" INTEGER,
    "is_read" INTEGER NOT NULL DEFAULT 0,
    "created_by" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "dedup_key" VARCHAR(150)
);
CREATE INDEX "notifications_student_id_idx" ON "notifications"("student_id");
CREATE INDEX "notifications_class_id_idx" ON "notifications"("class_id");
CREATE INDEX "notifications_dedup_key_idx" ON "notifications"("dedup_key");

-- CreateTable homework
CREATE TABLE "homework" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "class_id" INTEGER NOT NULL,
    "subject_id" INTEGER,
    "title" VARCHAR(150) NOT NULL,
    "description" TEXT,
    "due_date" DATE,
    "created_by" INTEGER NOT NULL,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "homework_class_id_idx" ON "homework"("class_id");
CREATE INDEX "homework_subject_id_idx" ON "homework"("subject_id");
CREATE INDEX "homework_created_by_idx" ON "homework"("created_by");

-- CreateTable homework_attachments
CREATE TABLE "homework_attachments" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "homework_id" INTEGER NOT NULL,
    "file_name" VARCHAR(255) NOT NULL,
    "file_path" VARCHAR(255) NOT NULL,
    "mime_type" VARCHAR(100),
    "file_size" INTEGER,
    "uploaded_by" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "homework_attachments_homework_id_idx" ON "homework_attachments"("homework_id");
CREATE INDEX "homework_attachments_uploaded_by_idx" ON "homework_attachments"("uploaded_by");

-- CreateTable guardian_links
CREATE TABLE "guardian_links" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "guardian_id" INTEGER NOT NULL,
    "student_id" INTEGER NOT NULL,
    "role" VARCHAR(20) NOT NULL DEFAULT 'sibling',
    "status" VARCHAR(20) NOT NULL DEFAULT 'pending',
    "requester_student_id" INTEGER,
    "decided_by" INTEGER,
    "remark" VARCHAR(255),
    "requested_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decided_at" TIMESTAMP,
    UNIQUE("student_id", "guardian_id")
);
CREATE INDEX "guardian_links_guardian_id_idx" ON "guardian_links"("guardian_id");
CREATE INDEX "guardian_links_requester_student_id_idx" ON "guardian_links"("requester_student_id");
CREATE INDEX "guardian_links_decided_by_idx" ON "guardian_links"("decided_by");

-- CreateTable class_teacher_requests
CREATE TABLE "class_teacher_requests" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "class_id" INTEGER NOT NULL,
    "teacher_id" INTEGER NOT NULL,
    "status" VARCHAR(20) NOT NULL DEFAULT 'pending',
    "note" VARCHAR(255),
    "decided_by" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decided_at" TIMESTAMP,
    UNIQUE("teacher_id", "class_id")
);
CREATE INDEX "class_teacher_requests_class_id_idx" ON "class_teacher_requests"("class_id");
CREATE INDEX "class_teacher_requests_decided_by_idx" ON "class_teacher_requests"("decided_by");

-- CreateTable mark_edit_requests
CREATE TABLE "mark_edit_requests" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "mark_id" INTEGER NOT NULL,
    "student_id" INTEGER NOT NULL,
    "exam_id" INTEGER NOT NULL,
    "teacher_id" INTEGER NOT NULL,
    "reason" TEXT,
    "status" VARCHAR(20) NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decided_at" TIMESTAMP,
    "decided_by" INTEGER
);
CREATE INDEX "mark_edit_requests_student_id_idx" ON "mark_edit_requests"("student_id");
CREATE INDEX "mark_edit_requests_exam_id_idx" ON "mark_edit_requests"("exam_id");
CREATE INDEX "mark_edit_requests_teacher_id_idx" ON "mark_edit_requests"("teacher_id");
CREATE INDEX "mark_edit_requests_decided_by_idx" ON "mark_edit_requests"("decided_by");
CREATE INDEX "mark_edit_requests_mark_id_idx" ON "mark_edit_requests"("mark_id");

-- CreateTable mark_edit_endorsements
CREATE TABLE "mark_edit_endorsements" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "request_id" INTEGER NOT NULL,
    "class_teacher_id" INTEGER NOT NULL,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE("request_id", "class_teacher_id")
);

-- CreateTable promotions
CREATE TABLE "promotions" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER NOT NULL,
    "event_id" INTEGER NOT NULL,
    "class_id" INTEGER NOT NULL,
    "group_name" VARCHAR(20),
    "from_class" VARCHAR(50) NOT NULL,
    "to_class" VARCHAR(50) NOT NULL,
    "promoted_roll" INTEGER,
    "decision" VARCHAR(20) NOT NULL DEFAULT 'promoted',
    "final_gpa" NUMERIC(4,2) NOT NULL DEFAULT 0,
    "recorded_by" INTEGER,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "passing_year" INTEGER,
    "destination_session_id" INTEGER,
    UNIQUE("event_id", "student_id")
);
CREATE INDEX "promotions_student_id_idx" ON "promotions"("student_id");
CREATE INDEX "promotions_recorded_by_idx" ON "promotions"("recorded_by");

-- CreateTable promotion_history
CREATE TABLE "promotion_history" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER NOT NULL,
    "from_class_id" INTEGER NOT NULL,
    "to_class_id" INTEGER,
    "final_gpa" NUMERIC(4,2) NOT NULL DEFAULT 0,
    "decision" VARCHAR(20) DEFAULT 'promoted',
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "admin_note" VARCHAR(255)
);
CREATE INDEX "promotion_history_student_id_idx" ON "promotion_history"("student_id");

-- CreateTable promotion_grace
CREATE TABLE "promotion_grace" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "class_id" INTEGER NOT NULL,
    "exam_type" VARCHAR(20) NOT NULL DEFAULT 'test',
    "grace_failed" INTEGER NOT NULL DEFAULT 0,
    "notes" VARCHAR(255),
    "updated_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE("exam_type", "class_id")
);
CREATE INDEX "promotion_grace_class_id_idx" ON "promotion_grace"("class_id");

-- CreateTable time_slots
CREATE TABLE "time_slots" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "slot_order" INTEGER NOT NULL UNIQUE,
    "label" VARCHAR(50) NOT NULL,
    "start_time" TIME,
    "end_time" TIME,
    "is_break" INTEGER DEFAULT 0
);

-- CreateTable routines
CREATE TABLE "routines" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "teacher_id" INTEGER NOT NULL,
    "subject_id" INTEGER NOT NULL,
    "day" INTEGER NOT NULL,
    "time_slot_id" INTEGER NOT NULL,
    "notes" TEXT,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "room" VARCHAR(30),
    UNIQUE("day", "time_slot_id", "teacher_id")
);
CREATE INDEX "routines_teacher_id_idx" ON "routines"("teacher_id");
CREATE INDEX "routines_subject_id_idx" ON "routines"("subject_id");
CREATE INDEX "routines_time_slot_id_idx" ON "routines"("time_slot_id");

-- CreateTable routine_entries
CREATE TABLE "routine_entries" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "class_id" INTEGER NOT NULL,
    "day" INTEGER NOT NULL,
    "period" INTEGER NOT NULL,
    "subject_id" INTEGER,
    "teacher_id" INTEGER,
    UNIQUE("class_id", "day", "period")
);

-- CreateTable routine_groups
CREATE TABLE "routine_groups" (
    "routine_id" INTEGER NOT NULL,
    "class_id" INTEGER NOT NULL,
    "group_name" VARCHAR(20) NOT NULL,
    PRIMARY KEY ("routine_id", "class_id", "group_name")
);
CREATE INDEX "routine_groups_class_id_idx" ON "routine_groups"("class_id");

-- CreateTable routine_sections
CREATE TABLE "routine_sections" (
    "routine_id" INTEGER NOT NULL,
    "class_id" INTEGER NOT NULL,
    "section" VARCHAR(20) NOT NULL,
    PRIMARY KEY ("routine_id", "class_id", "section")
);
CREATE INDEX "routine_sections_class_id_idx" ON "routine_sections"("class_id");

-- CreateTable routine_delete_requests
CREATE TABLE "routine_delete_requests" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "routine_id" INTEGER NOT NULL,
    "teacher_id" INTEGER NOT NULL,
    "subject_name" VARCHAR(150),
    "class_details" TEXT,
    "day" INTEGER,
    "time_slot_id" INTEGER,
    "reason" TEXT,
    "status" VARCHAR(20) NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decided_at" TIMESTAMP
);

-- CreateTable routine_notification_log
CREATE TABLE "routine_notification_log" (
    "id" BIGSERIAL NOT NULL PRIMARY KEY,
    "routine_id" INTEGER NOT NULL,
    "event_date" DATE NOT NULL,
    "event" VARCHAR(20) NOT NULL,
    "sent_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE("event_date", "event", "routine_id")
);
CREATE INDEX "routine_notification_log_routine_id_idx" ON "routine_notification_log"("routine_id");

-- CreateTable holidays
CREATE TABLE "holidays" (
    "date" DATE NOT NULL PRIMARY KEY,
    "title" VARCHAR(150) NOT NULL
);

-- CreateTable app_settings
CREATE TABLE "app_settings" (
    "setting_key" VARCHAR(60) NOT NULL PRIMARY KEY,
    "setting_value" TEXT
);

-- CreateTable activity_log
CREATE TABLE "activity_log" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "user_id" INTEGER,
    "action" VARCHAR(100) NOT NULL,
    "detail" TEXT,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "activity_log_user_id_idx" ON "activity_log"("user_id");
CREATE INDEX "activity_log_action_idx" ON "activity_log"("action");

-- CreateTable device_tokens
CREATE TABLE "device_tokens" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "user_id" INTEGER NOT NULL,
    "role" VARCHAR(20) NOT NULL,
    "fcm_token" TEXT NOT NULL UNIQUE,
    "platform" VARCHAR(20) NOT NULL DEFAULT 'android',
    "active" INTEGER NOT NULL DEFAULT 1,
    "last_seen" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "device_tokens_user_id_idx" ON "device_tokens"("user_id");
CREATE INDEX "device_tokens_role_active_idx" ON "device_tokens"("role", "active");

-- CreateTable subject_aliases
CREATE TABLE "subject_aliases" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "subject_id" INTEGER NOT NULL,
    "alias_name" VARCHAR(120) NOT NULL,
    "student_field" VARCHAR(50) NOT NULL DEFAULT 'religion',
    "field_value" VARCHAR(50) NOT NULL,
    "class_id" INTEGER,
    UNIQUE("student_field", "subject_id", "field_value", "class_id")
);
CREATE INDEX "subject_aliases_subject_id_idx" ON "subject_aliases"("subject_id");
CREATE INDEX "subject_aliases_class_id_idx" ON "subject_aliases"("class_id");

-- CreateTable leave_tickets
CREATE TABLE "leave_tickets" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "student_id" INTEGER NOT NULL,
    "guardian_id" INTEGER,
    "leave_date" DATE NOT NULL,
    "kind" VARCHAR(20) NOT NULL DEFAULT 'full_day',
    "reason" VARCHAR(500),
    "status" VARCHAR(20) NOT NULL DEFAULT 'pending',
    "decided_by" INTEGER,
    "decided_at" TIMESTAMP,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "leave_tickets_student_id_leave_date_idx" ON "leave_tickets"("student_id", "leave_date");
CREATE INDEX "leave_tickets_status_idx" ON "leave_tickets"("status");

-- CreateTable reexam_requests
CREATE TABLE "reexam_requests" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "guardian_id" INTEGER,
    "student_id" INTEGER NOT NULL,
    "event_id" INTEGER NOT NULL,
    "class_id" INTEGER,
    "reason" VARCHAR(1000),
    "status" VARCHAR(20) NOT NULL DEFAULT 'pending',
    "decided_by" INTEGER,
    "decided_at" TIMESTAMP,
    "admin_note" VARCHAR(500),
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "reexam_requests_status_idx" ON "reexam_requests"("status");
CREATE INDEX "reexam_requests_student_id_idx" ON "reexam_requests"("student_id");
CREATE INDEX "reexam_requests_event_id_idx" ON "reexam_requests"("event_id");

-- CreateTable designation_slots
CREATE TABLE "designation_slots" (
    "id" SERIAL NOT NULL PRIMARY KEY,
    "designation" VARCHAR(100) NOT NULL,
    "scope" VARCHAR(20) NOT NULL DEFAULT 'global',
    "class_id" INTEGER,
    "holder_user_id" INTEGER,
    "locked" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE("designation", "scope", "class_id")
);