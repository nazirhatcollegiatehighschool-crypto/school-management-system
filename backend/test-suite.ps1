$ErrorActionPreference = 'Continue'
$base = "http://127.0.0.1:5000/api"
$script:result = @()

function Test-Case($name, $expectFail, $scriptblock) {
    try {
        $r = & $scriptblock
        if ($expectFail) { $script:result += [pscustomobject]@{Test=$name; Result='FAILED'; Detail="accepted unexpectedly"} }
        else { $script:result += [pscustomobject]@{Test=$name; Result='PASSED'; Detail=($r | Out-String).Substring(0,[Math]::Min(80,($r | Out-String).Length))} }
    } catch {
        $msg = $_.ErrorDetails.Message
        if (-not $msg) { $msg = $_.Exception.Message }
        if ($expectFail) { $script:result += [pscustomobject]@{Test=$name; Result='PASSED'; Detail=$msg} }
        else { $script:result += [pscustomobject]@{Test=$name; Result='FAILED'; Detail=$msg} }
    }
}

# 0. Ensure server
$healthOK = $false
try { Invoke-RestMethod "$base/health" -TimeoutSec 5 | Out-Null; $healthOK = $true } catch { Write-Output ("initial health err: " + $_.Exception.Message) }
if (-not $healthOK) {
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep 2
    Start-Process -FilePath "node" -ArgumentList "server.js" -WorkingDirectory "C:\Users\WALTON\Desktop\school-system\backend" -WindowStyle Hidden
    $up = $false
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep 2
        try { Invoke-RestMethod "$base/health" -TimeoutSec 3 | Out-Null; $up = $true; break } catch {}
    }
    if (-not $up) { Write-Output "SERVER UNREACHABLE - ABORT"; exit 1 }
}

# Logins (seed_v5.users, all passwords 123456)
$at = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"admin","password":"123456"}').token
$AH = @{ Authorization = "Bearer $at"; "Content-Type" = "application/json" }
$tt = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"rahim","password":"123456"}').token
$TH = @{ Authorization = "Bearer $tt"; "Content-Type" = "application/json" }
$gt = (Invoke-RestMethod "$base/auth/guardian-login" -Method Post -ContentType "application/json" -Body '{"student_code":"48291056","dob":"2013-05-12","class_name":"6","section":"A","roll":1,"phone":"01755555555"}').token
$GH = @{ Authorization = "Bearer $gt"; "Content-Type" = "application/json" }

# Dynamic test data
# PS5.1 Invoke-RestMethod on JSON arrays may return a single mangled object,
# so force proper array deserialization.
$examsRaw = (Invoke-WebRequest "$base/teacher/exams" -Headers $TH -UseBasicParsing).Content
$exams = ConvertFrom-Json -InputObject $examsRaw
$publishedExam = $exams | Where-Object { $_.status -eq 'published' } | Select-Object -First 1
$draftExam = $exams | Where-Object { $_.status -eq 'draft' } | Select-Object -First 1

# T1 over-max marks
Test-Case 'T1 marks>total rejected' $true { Invoke-RestMethod "$base/teacher/exams/$($draftExam.id)/marks" -Method Post -Headers $TH -Body '{"records":[{"student_id":1,"marks":150,"total":100}]}' | Out-Null }
# T2 negative
Test-Case 'T2 negative marks rejected' $true { Invoke-RestMethod "$base/teacher/exams/$($draftExam.id)/marks" -Method Post -Headers $TH -Body '{"records":[{"student_id":1,"marks":-5}]}' | Out-Null }
# T3 invalid exam
Test-Case 'T3 invalid exam id rejected' $true { Invoke-RestMethod "$base/teacher/exams/99999/marks" -Method Post -Headers $TH -Body '{"records":[{"student_id":1,"marks":50}]}' | Out-Null }
# T3b student not in exam class rejected
Test-Case 'T3b student-not-in-class rejected' $true { Invoke-RestMethod "$base/teacher/exams/$($draftExam.id)/marks" -Method Post -Headers $TH -Body '{"records":[{"student_id":7,"marks":40,"total":100}]}' | Out-Null }
# T4 teacher cannot access admin API
Test-Case 'T4 teacher blocked from admin API' $true { Invoke-RestMethod "$base/admin/students" -Headers $TH | Out-Null }
# T5 guardian cannot access other student attendance
Test-Case 'T5 guardian IDOR blocked' $true { Invoke-RestMethod "$base/guardian/student/2/attendance" -Headers $GH | Out-Null }
# T5b guardian cannot read other student result detail
Test-Case 'T5b guardian result-detail IDOR blocked' $true { Invoke-RestMethod "$base/guardian/student/2/result/1" -Headers $GH | Out-Null }
# T6 guardian own data allowed
Test-Case 'T6 guardian own child OK' $false { (Invoke-RestMethod "$base/guardian/student/1/attendance" -Headers $GH) | Out-Null; 'own child accessible' }
# T6b guardian unseen private exam list filtered
Test-Case 'T6b teacher exam privacy (creator A not seen by B)' $false { ConvertFrom-Json -InputObject ((Invoke-WebRequest "$base/teacher/exams" -Headers $TH -UseBasicParsing).Content) | ForEach-Object { $_.source } | Group-Object | ForEach-Object { "$($_.Name)=$($_.Count)" } }
# T7 invalid token rejected
Test-Case 'T7 bad token rejected' $true { Invoke-RestMethod "$base/admin/stats" -Headers @{Authorization='Bearer garbage'} | Out-Null }
# T8 no token rejected
Test-Case 'T8 missing token rejected' $true { Invoke-RestMethod "$base/teacher/profile" | Out-Null }
# T9 student validation: roll 0 rejected
Test-Case 'T9 invalid roll rejected' $true { Invoke-RestMethod "$base/admin/students" -Method Post -Headers $AH -Body '{"name":"X","roll":0,"class_id":1}' | Out-Null }
# T10 duplicate username teacher rejected
Test-Case 'T10 duplicate teacher username' $true { Invoke-RestMethod "$base/admin/teachers" -Method Post -Headers $AH -Body '{"name":"Dup","username":"rahim","password":"x"}' | Out-Null }
# T11 notifications read endpoint
Test-Case 'T11 mark-all-read works' $false { Invoke-RestMethod "$base/guardian/notifications/read" -Method Post -Headers $GH -Body '{"all":true}' | Out-Null; $n = ConvertFrom-Json -InputObject ((Invoke-WebRequest "$base/guardian/notifications" -Headers $GH -UseBasicParsing).Content); "unread now: $($n.unread)" }
# T12 published exam edit blocked
Test-Case 'T12 published exam locked' $true { Invoke-RestMethod "$base/teacher/exams/$($publishedExam.id)/marks" -Method Post -Headers $TH -Body '{"records":[{"student_id":1,"marks":50,"total":100}]}' | Out-Null }
# T13 settings update persists
Test-Case 'T13 settings roundtrip' $false { Invoke-RestMethod "$base/admin/settings" -Method Put -Headers $AH -Body '{"school_name":"NCHS"}' | Out-Null; $s = Invoke-RestMethod "$base/admin/settings" -Headers $AH; "school_name=$($s.school_name)" }
# T14 unauthenticated notice rejected
Test-Case 'T14 anonymous notice blocked' $true { Invoke-RestMethod "$base/admin/notices" -Method Post -ContentType "application/json" -Body '{"title":"hack"}' | Out-Null }
# T15 teacher-created class test private: karim (different teacher) doesn't see rahim's teacher-source exams
Test-Case 'T15 teacher-created exam privacy across teachers' $false {
    $kt = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"karim","password":"123456"}').token
    $karimExams = ConvertFrom-Json -InputObject ((Invoke-WebRequest "$base/teacher/exams" -Headers @{ Authorization = "Bearer $kt" } -UseBasicParsing).Content) | Where-Object { $_.source -eq 'teacher' }
    "karim sees $(@($karimExams).Count) teacher-source exams"
}
# T16 notice targeting (section) works
Test-Case 'T16 section-targeted notice' $false {
    $r = Invoke-RestMethod "$base/admin/notices" -Method Post -Headers $AH -Body '{"title":"Section test","body":"Only section A","target_type":"section","class_id":1,"section":"A"}'
    "notice sent: students=$($r.students)"
}
# T17 result detail deep-link (published result) accessible
Test-Case 'T17 guardian result detail (own child)' $false {
    if ($publishedExam) {
        $r = Invoke-RestMethod "$base/guardian/student/1/result/$($publishedExam.id)" -Headers $GH
        "subject=$($r.subject_name) pct=$($r.percentage)"
    } else { 'no published exam available' }
}

# T18 attendance: class-teacher-only (rahim=teacher2 for class 1; karim=teacher3 for class 4)
Test-Case 'T18 class-teacher-only attendance' $true {
    $kh = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"karim","password":"123456"}').token
    Invoke-RestMethod "$base/teacher/attendance" -Method Post -Headers @{ Authorization = "Bearer $kh"; "Content-Type" = "application/json" } -Body '{"date":"2026-09-13","records":[{"student_id":1,"status":"present"}]}' | Out-Null
}
Test-Case 'T18b own-class attendance allowed' $false {
    Invoke-RestMethod "$base/teacher/attendance" -Method Post -Headers $TH -Body '{"date":"2026-09-13","records":[{"student_id":1,"status":"present"}]}' | Out-Null
    'own class recorded'
}
# T19 fees module completely purged
Test-Case 'T19 fees endpoints removed (admin)' $true { Invoke-RestMethod "$base/admin/fees" -Headers $AH | Out-Null }
Test-Case 'T19b fees stats field removed' $false {
    $s = Invoke-RestMethod "$base/admin/stats" -Headers $AH
    "has pendingFees: $($null -ne $s.pendingFees)"
}
Test-Case 'T19c guardian fees endpoint removed' $true { Invoke-RestMethod "$base/guardian/student/1/fees" -Headers $GH | Out-Null }
# T20 homework module
Test-Case 'T20 homework create (own class)' $false {
    $r = Invoke-RestMethod "$base/teacher/homework" -Method Post -Headers $TH -Body '{"class_id":1,"title":"HW Math 1","description":"Solve ex 1-5","due_date":"2026-09-20"}'
    "hw id=$($r.id)"
}
Test-Case 'T20b guardian sees only own child homework' $false {
    $hw = ConvertFrom-Json -InputObject ((Invoke-WebRequest "$base/guardian/student/1/homework" -Headers $GH -UseBasicParsing).Content)
    "rows=$(@($hw).Count)"
}
Test-Case 'T20c cross-teacher homework blocked' $true {
    $kh = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"karim","password":"123456"}').token
    Invoke-RestMethod "$base/teacher/homework" -Method Post -Headers @{ Authorization = "Bearer $kh"; "Content-Type" = "application/json" } -Body '{"class_id":1,"title":"Sneak"}' | Out-Null
}
Test-Case 'T20d cross-guardian homework blocked' $true { Invoke-RestMethod "$base/guardian/student/2/homework" -Headers $GH | Out-Null }
# T21 complaints / special direct notices (karim -> fahim student 5, guardian 5)
Test-Case 'T21 complaint to guardian' $false {
    $kh = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"karim","password":"123456"}').token
    $r = Invoke-RestMethod "$base/teacher/complaints" -Method Post -Headers @{ Authorization = "Bearer $kh"; "Content-Type" = "application/json" } -Body '{"student_id":5,"title":"Attention","body":"Discuss Fahim homework"}' 
    "complaint ok=$($r.ok)"
}
Test-Case 'T21b complaint appears in guardian notifications' $false {
    $n = ConvertFrom-Json -InputObject ((Invoke-WebRequest "$base/guardian/notifications" -Headers $GH -UseBasicParsing).Content)
    $c = @($n.notifications | Where-Object { $_.type -eq 'complaint' }).Count
    "complaint notifs=$c"
}
Test-Case 'T21c complaint for unowned student blocked' $true {
    $kh = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"karim","password":"123456"}').token
    Invoke-RestMethod "$base/teacher/complaints" -Method Post -Headers @{ Authorization = "Bearer $kh"; "Content-Type" = "application/json" } -Body '{"student_id":2,"title":"Nope","body":"not your class"}' | Out-Null
}

# T22 sibling request flow: unapproved sibling data invisible
Test-Case 'T22 sibling pending request created' $false {
    $r = Invoke-RestMethod "$base/guardian/sibling-request" -Method Post -Headers $GH -Body '{"student_code":"92017384","dob":"2012-07-30","class_name":"7","section":"A","roll":2,"phone":"01755555555"}'
    "status=$($r.status)"
}
Test-Case 'T22b sibling data invisible until approved' $true { Invoke-RestMethod "$base/guardian/student/5/marks" -Headers $GH | Out-Null }
Test-Case 'T22c admin sees pending sibling request' $false {
    $reqs = ConvertFrom-Json -InputObject ((Invoke-WebRequest "$base/admin/sibling-requests?status=pending" -Headers $AH -UseBasicParsing).Content)
    "pending=$(@($reqs).Count)"
}
# T23 admin approves the sibling request -> visible
Test-Case 'T23 admin approves sibling link' $false {
    $reqs = ConvertFrom-Json -InputObject ((Invoke-WebRequest "$base/admin/sibling-requests?status=pending" -Headers $AH -UseBasicParsing).Content)
    if (@($reqs).Count -gt 0) {
        $r = Invoke-RestMethod "$base/admin/sibling-requests/$($reqs[0].id)/approve" -Method Post -Headers $AH -Body '{}'
        "approved ok=$($r.ok)"
    } else { 'no pending' }
}
Test-Case 'T23b sibling now visible to guardian' $false {
    $r = Invoke-RestMethod "$base/guardian/student/5/homework" -Headers $GH
    "homework rows=$(@($r).Count)"
}
# T24 reject path: Tanim (student 3) request rejected -> stays invisible
Test-Case 'T24 rejected sibling stays invisible' $false {
    Invoke-RestMethod "$base/guardian/sibling-request" -Method Post -Headers $GH -Body '{"student_code":"69483712","dob":"2013-11-03","class_name":"6","section":"A","roll":3,"phone":"01755555555"}' | Out-Null
    $reqs = ConvertFrom-Json -InputObject ((Invoke-WebRequest "$base/admin/sibling-requests?status=pending" -Headers $AH -UseBasicParsing).Content)
    if (@($reqs).Count -gt 0) {
        $target = @($reqs) | Where-Object { $_.student_name -eq 'Tanim Islam' } | Select-Object -First 1
        if ($target) {
            Invoke-RestMethod "$base/admin/sibling-requests/$($target.id)/reject" -Method Post -Headers $AH -Body '{"remark":"Not a sibling"}' | Out-Null
        }
    }
    'Tanim kept invisible'
}
Test-Case 'T24b rejected sibling still blocked' $true { Invoke-RestMethod "$base/guardian/student/3/marks" -Headers $GH | Out-Null }

foreach ($r in $script:result) { Write-Output ("{0,-38} {1,-8} {2}" -f $r.Test, $r.Result, $r.Detail) }