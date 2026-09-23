import { useState, useEffect } from 'react';
import { api } from '../api';

export default function SiblingRequests() {
  const [tab, setTab] = useState('pending');
  const [rows, setRows] = useState([]);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [rejecting, setRejecting] = useState(null);
  const [rejectText, setRejectText] = useState('');

  const load = () => api('/admin/sibling-requests?status=' + tab).then(setRows).catch(e => setErr(e.message));
  useEffect(load, [tab]);

  const act = async (id, action) => {
    setErr(''); setMsg('');
    try {
      await api('/admin/sibling-requests/' + id + '/' + action, {
        method: 'POST',
        body: action === 'reject' ? { remark: rejectText || 'Request rejected' } : {}
      });
      setMsg(action === 'approve' ? 'অনুমোদিত হয়েছে — guardian-এর app-এ এখন sibling দেখা যাবে' : 'বাতিল করা হয়েছে');
      setRejecting(null); setRejectText(''); load();
    } catch (ex) { setErr(ex.message); }
  };

  return (
    <div>
      {err && <div className="error-msg">{err}</div>}
      {msg && <div className="success-msg">{msg}</div>}
      <div className="panel">
        <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
          {['pending', 'approved', 'rejected'].map(s => (
            <button key={s} className={'btn sm ' + (tab === s ? '' : 'ghost')} onClick={() => setTab(s)}>
              {s.charAt(0).toUpperCase() + s.slice(1)}
            </button>
          ))}
        </div>
        <table>
          <thead>
            <tr><th>Guardian</th><th>Sibling</th><th>Class</th><th>Roll</th><th>Asked by</th><th>Requested</th><th>Actions</th></tr>
          </thead>
          <tbody>
            {rows.map(r => (
              <tr key={r.id}>
                <td>{r.guardian_name}<br /><small>{r.guardian_phone}</small></td>
                <td>{r.student_name}<br /><small>{r.student_code} • DOB {String(r.dob || '').slice(0, 10)}</small></td>
                <td>{r.class_name} ({r.section})</td>
                <td>{r.roll}</td>
                <td>{r.requester_name ? `${r.requester_name} (roll ${r.requester_roll})` : '-'}</td>
                <td>{String(r.requested_at || '').slice(0, 16).replace('T', ' ')}</td>
                <td>
                  {(r.status === 'pending') ? (
                    <>
                      <button className="btn sm" onClick={() => act(r.id, 'approve')}>Approve</button>{' '}
                      <button className="btn sm red" onClick={() => setRejecting(r)}>Reject</button>
                    </>
                  ) : (
                    <small>{tab === 'rejected' ? (r.remark || 'rejected') : '✓ approved'}</small>
                  )}
                </td>
              </tr>
            ))}
            {rows.length === 0 && <tr><td colSpan="7" style={{ textAlign: 'center', color: 'grey' }}>কোনো request নেই</td></tr>}
          </tbody>
        </table>
      </div>

      {rejecting && (
        <div className="modal-bg" onClick={() => setRejecting(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <h3>Reject sibling request — {rejecting.student_name}</h3>
            <div className="form-row">
              <div><label>Reason (optional)</label>
                <input value={rejectText} onChange={e => setRejectText(e.target.value)} placeholder="e.g. roll number mismatch" />
              </div>
            </div>
            <div className="modal-actions">
              <button type="button" className="btn ghost" onClick={() => setRejecting(null)}>Cancel</button>
              <button type="button" className="btn red" onClick={() => act(rejecting.id, 'reject')}>Reject</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}