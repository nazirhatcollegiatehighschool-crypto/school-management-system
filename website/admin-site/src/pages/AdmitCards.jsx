import { useState, useEffect } from 'react';
import { api } from '../api';

// Admit cards in the transcript-generator visual language:
// emblem header, serial, 2-col info grid, subject checklist, dual signatures.
const dobFmt = v => {
  if (!v) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : String(v).slice(0, 10);
};

export default function AdmitCards() {
  const [classes, setClasses] = useState([]);
  const [events, setEvents] = useState([]);
  const [subjects, setSubjects] = useState([]);
  const [students, setStudents] = useState([]);
  const [classId, setClassId] = useState('');
  const [eventId, setEventId] = useState('');
  const [settings, setSettings] = useState({});
  const [err, setErr] = useState('');

  useEffect(() => {
    api('/admin/classes').then(setClasses).catch(e => setErr(e.message));
    api('/results/events').then(setEvents).catch(() => {});
    api('/admin/subjects').then(setSubjects).catch(() => {});
    api('/admin/settings').then(setSettings).catch(() => {});
  }, []);
  useEffect(() => {
    if (!classId) return;
    api('/admin/students').then(all => setStudents(all.filter(s => s.class_id === Number(classId)))).catch(() => {});
  }, [classId]);

  const ev = events.find(e => e.id === Number(eventId));
  const cls = classes.find(c => c.id === Number(classId));
  const clsSubjects = subjects.filter(s => s.class_id === Number(classId));
  const school = settings.school_name || 'Nazirhat Collegiate High School';
  const year = ev && ev.year ? ev.year : (ev ? (ev.session_name || '') : '');
  const secLabel = cls ? (cls.group_name ? `${cls.group_name} Group` : `Section ${cls.section}`) : '';
  // 2 cards per row, like the transcript sheet.
  const pages = [];
  for (let i = 0; i < students.length; i += 2) pages.push(students.slice(i, i + 2));

  return (
    <div>
      {err && <div className="error-msg no-print">{err}</div>}
      <div className="panel no-print">
        <h3>Admit Cards — প্রবেশপত্র</h3>
        <div className="doc-toolbar">
          <div><label>Class</label>
            <select value={classId} onChange={e => setClassId(e.target.value)}>
              <option value="">Select class</option>
              {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}</option>)}
            </select>
          </div>
          <div><label>Exam Event</label>
            <select value={eventId} onChange={e => setEventId(e.target.value)}>
              <option value="">Select event</option>
              {events.map(ev2 => <option key={ev2.id} value={ev2.id}>{ev2.name}</option>)}
            </select>
          </div>
        </div>
      </div>

      {classId && eventId && students.length > 0 && (
        <div className="print-sheet">
          <div className="doc-header no-print" style={{ border: 'none' }}>
            <h2 style={{ fontSize: 18 }}>Preview — {students.length} admit cards</h2>
          </div>
          <div className="ac-sheet">
            {pages.map((pg, pi) => (
              <div className="ac-page" key={pi}>
                {pg.map((s, i) => (
                  <div className="ac-card" key={s.id}>
                    <div className="ac-head">
                      <span className="ac-emblem">N</span>
                      <div className="ac-institution">
                        <b>{school}</b><br />
                        <span>{ev ? ev.name : ''} {year}</span>
                      </div>
                      <span className="ac-serial">Sl. {pi * 2 + i + 1}</span>
                    </div>
                    <div className="ac-title">ADMIT CARD — {ev ? ev.name.toUpperCase() : ''} {year}</div>
                    <div className="ac-info">
                      <p><span>Student Name</span><b>{s.name}</b></p>
                      <p><span>Student ID</span><b>{s.student_code}</b></p>
                      <p><span>Roll No</span><b>{s.roll}</b></p>
                      <p><span>Class</span><b>{s.class_name} ({secLabel})</b></p>
                      <p><span>Father&rsquo;s Name</span><b>{s.father_name || '—'}</b></p>
                      <p><span>Mother&rsquo;s Name</span><b>{s.mother_name || '—'}</b></p>
                      <p><span>Date of Birth</span><b>{dobFmt(s.dob)}</b></p>
                      <p><span>Exam Name</span><b>{ev ? ev.name : ''}</b></p>
                    </div>
                    <div className="ac-subjects">
                      <div className="ac-subjects-title">SUBJECTS</div>
                      <div className="ac-subjects-grid">
                        {clsSubjects.map(sub => (
                          <span key={sub.id}><i></i>{sub.name}{sub.subject_code ? ` (${sub.subject_code})` : ''}</span>
                        ))}
                      </div>
                    </div>
                    <div className="ac-sigs">
                      <div className="ac-sig"><div className="ac-sig-line"></div><span>Controller of Examinations</span></div>
                      <div className="ac-sig"><div className="ac-sig-line"></div><span>Headmaster / Principal</span></div>
                    </div>
                  </div>
                ))}
              </div>
            ))}
          </div>
          <div style={{ marginTop: 16 }} className="no-print">
            <button className="btn" onClick={() => window.print()}>🖨️ Print All Admit Cards</button>
          </div>
        </div>
      )}
    </div>
  );
}
