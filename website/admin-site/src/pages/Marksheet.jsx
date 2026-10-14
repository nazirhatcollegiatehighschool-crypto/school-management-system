import { useState, useEffect } from 'react';
import { api, getToken } from '../api';

export default function Marksheet() {
  const [classes, setClasses] = useState([]);
  const [students, setStudents] = useState([]);
  const [events, setEvents] = useState([]);
  const [classId, setClassId] = useState('');
  const [studentId, setStudentId] = useState('');
  const [eventId, setEventId] = useState('');
  const [sheet, setSheet] = useState(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    api('/admin/classes').then(setClasses).catch(() => {});
    api('/results/events').then(setEvents).catch(() => {});
  }, []);
  useEffect(() => {
    if (!classId) return;
    api('/admin/students').then(all => setStudents(all.filter(s => s.class_id === Number(classId)))).catch(() => {});
  }, [classId]);

  const load = async () => {
    if (!studentId || !eventId) return;
    setErr(''); setSheet(null);
    try {
      setSheet(await api(`/results/marksheet/${studentId}/${eventId}`));
    } catch (ex) { setErr(ex.message); }
  };

  const downloadPdf = async () => {
    if (!studentId || !eventId) return;
    setErr('');
    try {
      const res = await fetch(`/api/results/marksheet-pdf/${studentId}/${eventId}`, {
        headers: { Authorization: 'Bearer ' + getToken() }
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error || 'PDF download failed');
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `marksheet_${studentId}_event${eventId}.pdf`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (ex) { setErr(ex.message); }
  };

  const remarkFor = gpa => {
    if (gpa == null) return '';
    if (gpa >= 4.5) return 'অসাধারণ ফলাফল। ধারাবাহিকতা বজায় রাখার জন্য উৎসাহিত করা হচ্ছে।';
    if (gpa >= 4.0) return 'খুব ভালো ফলাফল। আরও অধ্যবসায়ী হলে শ্রেষ্ঠ হওয়া সম্ভব।';
    if (gpa >= 3.5) return 'ভালো ফলাফল। দুর্বল বিষয়ে বেশি মনোযোগ দিতে হবে।';
    if (gpa >= 2.0) return 'মোটামুটি ফলাফল। নিয়মিত পড়াশোনা বাড়ানো প্রয়োজন।';
    if (gpa >= 1.0) return 'সন্তোষজনক। বিশেষ যত্ন ও পড়াশোনায় উন্নতি সম্ভব।';
    return 'আরও পরিশ্রম ও অভিভাবকের তত্ত্বাবধান প্রয়োজন।';
  };

  return (
    <div>
      {err && <div className="error-msg no-print">{err}</div>}
      <div className="panel no-print">
        <h3>Marksheet — ছাপার উপযোগী</h3>
        <div className="doc-toolbar">
          <div><label>Class</label>
            <select value={classId} onChange={e => { setClassId(e.target.value); setStudentId(''); }}>
              <option value="">Select class</option>
              {classes.map(c => <option key={c.id} value={c.id}>{c.name} - {c.section}</option>)}
            </select>
          </div>
          <div><label>Student</label>
            <select value={studentId} onChange={e => setStudentId(e.target.value)}>
              <option value="">Select student</option>
              {students.map(s => <option key={s.id} value={s.id}>{s.roll}. {s.name}</option>)}
            </select>
          </div>
          <div><label>Exam Event</label>
            <select value={eventId} onChange={e => setEventId(e.target.value)}>
              <option value="">Select event</option>
              {events.map(ev => <option key={ev.id} value={ev.id}>{ev.name}</option>)}
            </select>
          </div>
          <button className="btn" disabled={!studentId || !eventId} onClick={load}>Generate</button>
        </div>
      </div>

      {sheet && sheet.result && (
        <div className="print-sheet" style={{ maxWidth: 800, margin: '0 auto' }}>
          <div className="doc-header">
            <h1>{sheet.settings.school_name || 'My School'}</h1>
            <div className="addr">{sheet.settings.school_address}</div>
            {sheet.settings.school_eiin && <div className="eiin">EIIN: {sheet.settings.school_eiin}</div>}
          </div>
          <div className="doc-title">{sheet.event ? sheet.event.name : ''}{sheet.event && sheet.event.year ? ` ${sheet.event.year}` : ''} — ACADEMIC MARKSHEET</div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: '#475569', marginBottom: 8 }}>
            <span><b>Serial No:</b> {sheet.serial_no || '—'}</span>
            <span><b>Record No:</b> {sheet.student.birth_cert_no || sheet.student.student_code}</span>
          </div>

          <table style={{ width: '100%', border: 'none', marginBottom: 8 }}>
            <tbody>
              <tr style={{ border: 'none' }}>
                <td style={{ border: 'none', verticalAlign: 'top' }}>
                  <table style={{ border: 'none' }}>
                    <tbody>
                      <tr><td style={{ border: 'none' }}><b>Name:</b></td><td style={{ border: 'none' }}>{sheet.student.name}</td></tr>
                      <tr><td style={{ border: 'none' }}><b>ID:</b></td><td style={{ border: 'none' }}>{sheet.student.student_code}</td></tr>
                      <tr><td style={{ border: 'none' }}><b>Class:</b></td><td style={{ border: 'none' }}>{sheet.student.class_name} ({sheet.student.section}){sheet.student.group_name ? ` [${sheet.student.group_name}]` : ''}</td></tr>
                      <tr><td style={{ border: 'none' }}><b>Roll:</b></td><td style={{ border: 'none' }}>{sheet.student.roll}</td></tr>
                      <tr><td style={{ border: 'none' }}><b>DOB:</b></td><td style={{ border: 'none' }}>{sheet.student.dob ? String(sheet.student.dob).slice(0, 10) : '-'}</td></tr>
                    </tbody>
                  </table>
                </td>
                <td style={{ border: 'none', width: 100 }}>
                  <div className="stu-photo">{sheet.student.photo ? <img src={`/uploads/${sheet.student.photo}`} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : 'Photo'}</div>
                </td>
              </tr>
            </tbody>
          </table>

          <div style={{ display: 'flex', gap: 16, marginBottom: 10, flexWrap: 'wrap' }}>
            <table className="mark-table" style={{ width: 'auto', fontSize: 12 }}>
              <caption style={{ textAlign: 'left', fontWeight: 700, padding: '4px 0' }}>Grading Scale</caption>
              <thead><tr><th>Letter</th><th>Interval</th><th>GP</th></tr></thead>
              <tbody>
                {[['A+', '80–100', '5.0'], ['A', '70–79', '4.0'], ['A-', '60–69', '3.5'], ['B', '50–59', '3.0'], ['C', '40–49', '2.0'], ['D', '33–39', '1.0'], ['F', '0–32', '0.0']].map(r => (
                  <tr key={r[0]}><td><b>{r[0]}</b></td><td>{r[1]}</td><td>{r[2]}</td></tr>
                ))}
              </tbody>
            </table>
            <div style={{ fontSize: 13, lineHeight: 2 }}>
              <div><b>Class Highest GPA:</b> {sheet.class_highest_gpa != null ? Number(sheet.class_highest_gpa).toFixed(2) : '—'}</div>
              <div><b>Attendance:</b> {(sheet.attendance || []).map(a => `${a.status}: ${a.c}`).join(' • ') || '—'}</div>
            </div>
          </div>

          <table className="mark-table" style={{ width: '100%' }}>
            <thead>
              <tr><th>Sl.</th><th>Subject</th><th>Papers</th><th>Marks</th><th>Full</th><th>%</th><th>Letter</th><th>GP</th></tr>
            </thead>
            <tbody>
              {sheet.result.families.filter(f => !f.is_optional).map((f, i) => (
                <tr key={f.subject}>
                  <td>{i + 1}</td>
                  <td className="subj"><b>{f.subject}</b></td>
                  <td>{f.papers.join(', ')}</td>
                  <td>{f.absent ? '—' : f.total}</td>
                  <td>{f.full}</td>
                  <td>{f.absent ? '—' : f.scaled}</td>
                  <td>{f.letter_grade}</td>
                  <td>{f.grade_point.toFixed(2)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          {sheet.result.families.some(f => f.is_optional) && (
            <table className="mark-table" style={{ width: '100%', marginTop: 10 }}>
              <thead>
                <tr><th>Sl.</th><th>Fourth Subject (Optional)</th><th>Marks</th><th>Letter</th><th>GP</th></tr>
              </thead>
              <tbody>
                {sheet.result.families.filter(f => f.is_optional).map((f, i) => (
                  <tr key={f.subject}>
                    <td>{i + 1}</td>
                    <td className="subj"><b>{f.subject}</b></td>
                    <td>{f.absent ? '—' : f.total}</td>
                    <td>{f.letter_grade}</td>
                    <td>{f.grade_point.toFixed(2)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          <div className="result-box">
            <span>GPA: {sheet.result.final_gpa.toFixed(2)}</span>
            {sheet.result.gpa_4th_bonus > 0 && <span style={{ color: '#16a34a' }}>4th Subject Bonus: +{sheet.result.gpa_4th_bonus}</span>}
            <span style={{ color: sheet.result.result_status === 'PASSED' ? '#16a34a' : '#dc2626' }}>
              {sheet.result.result_status === 'PASSED' ? '✔ PASSED' : sheet.result.result_status}
            </span>
          </div>

          <p style={{ marginTop: 14, fontSize: 14 }}><b>Remarks:</b> {sheet.remarks || remarkFor(sheet.result.final_gpa)}</p>

          <div className="sign-row">
            <span>Class Teacher</span>
            <span>Controller of Examinations</span>
            <span>{sheet.settings.headmaster || 'Headmaster'}</span>
          </div>
          <div style={{ marginTop: 10, fontSize: 12, color: '#475569' }}>
            Date of Publication of Result: {sheet.event && sheet.event.published_at ? String(sheet.event.published_at).slice(0, 10) : '—'}
          </div>

          <div style={{ marginTop: 16 }} className="no-print">
            <button className="btn" onClick={() => window.print()}>🖨️ Print Marksheet</button>
            <button className="btn ghost" style={{ marginLeft: 8 }} onClick={downloadPdf}>📄 Download PDF</button>
          </div>
        </div>
      )}
      {sheet && !sheet.result && (
        <div className="panel no-print">এই student-এর এই exam event-এ কোনো marks নেই। আগে Results page-এ Compute করুন।</div>
      )}
    </div>
  );
}