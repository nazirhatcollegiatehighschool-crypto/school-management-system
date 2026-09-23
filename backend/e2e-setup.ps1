$ErrorActionPreference = 'Continue'
$base = "http://127.0.0.1:5000/api"
try { Invoke-RestMethod "$base/health" -TimeoutSec 5 | Out-Null } catch { Write-Output "SERVER DOWN"; exit 1 }

$at = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"admin","password":"123456"}').token
$AH = @{ Authorization = "Bearer $at"; "Content-Type" = "application/json" }

# Create exams for class 6A (id=1) and 9 Science (id=10) under event 1
foreach ($cid in @(1, 10)) {
    $allSubs = @(Invoke-RestMethod "$base/admin/subjects" -Headers $AH)
    $subs = @($allSubs | Where-Object { $_.class_id -eq $cid })
    foreach ($s in $subs) {
        try { Invoke-RestMethod "$base/admin/exams" -Method Post -Headers $AH -Body ('{"name":"First Terminal - ' + $s.name + '","exam_type":"final","class_id":' + $cid + ',"subject_id":' + $s.id + ',"event_id":1}') | Out-Null } catch {}
    }
    Write-Output "class ${cid}: created $($subs.Count) exams"
}

function Enter-Marks($token, $examId, $students, $seed) {
    $recs = @()
    $n = 0
    foreach ($s in $students) {
        $m = 35 + (($seed + $s.roll * 7 + $n * 13) % 60)
        $recs += '{"student_id":' + $s.id + ',"marks":' + $m + ',"comment":"ভালো চেষ্টা করেছে"}'
        $n++
    }
    Invoke-RestMethod "$base/teacher/exams/$examId/marks" -Method Post -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } -Body ('{"records":[' + ($recs -join ',') + ']}') | Out-Null
}

# rahim: class 6A teacher — enter + publish his exams
$tt = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"rahim","password":"123456"}').token
$TH = @{ Authorization = "Bearer $tt"; "Content-Type" = "application/json" }
$st6 = @(Invoke-RestMethod "$base/teacher/classes/1/students" -Headers $TH)
$texams = @(Invoke-RestMethod "$base/teacher/exams" -Headers $TH | Where-Object { $_.class_id -eq 1 -and $_.event_id -eq 1 })
Write-Output "rahim exams for 6A: $($texams.Count)"
$seed = 10
foreach ($e in $texams) {
    try {
        Enter-Marks $tt $e.id $st6 $seed
        $pub = Invoke-RestMethod "$base/teacher/exams/$($e.id)/publish" -Method Post -Headers $TH
        Write-Output "  rahim published $($e.name) -> notified $($pub.notified)"
    } catch { Write-Output "  fail $($e.name): $($_.ErrorDetails.Message)" }
    $seed += 17
}

# salma: class 9 Science teacher
$st = (Invoke-RestMethod "$base/auth/login" -Method Post -ContentType "application/json" -Body '{"username":"salma","password":"123456"}').token
$SH = @{ Authorization = "Bearer $st"; "Content-Type" = "application/json" }
$st9 = @(Invoke-RestMethod "$base/teacher/classes/10/students" -Headers $SH)
$sexams = @(Invoke-RestMethod "$base/teacher/exams" -Headers $SH | Where-Object { $_.class_id -eq 10 -and $_.event_id -eq 1 })
Write-Output "salma exams for 9-Science: $($sexams.Count)"
$seed = 40
foreach ($e in $sexams) {
    try {
        $recs = @(); $n = 0
        foreach ($s in $st9) {
            $tot = 35 + (($seed + $s.roll * 11 + $n * 7) % 60)
            $recs += '{"student_id":' + $s.id + ',"marks":' + $tot + '}'
            $n++
        }
        Invoke-RestMethod "$base/teacher/exams/$($e.id)/marks" -Method Post -Headers $SH -Body ('{"records":[' + ($recs -join ',') + ']}') | Out-Null
        $pub = Invoke-RestMethod "$base/teacher/exams/$($e.id)/publish" -Method Post -Headers $SH
        Write-Output "  salma published $($e.name) -> notified $($pub.notified)"
    } catch { Write-Output "  fail $($e.name): $($_.ErrorDetails.Message)" }
    $seed += 23
}

# Compute results
foreach ($cid in @(1, 10)) {
    $r = Invoke-RestMethod "$base/results/results/compute" -Method Post -Headers $AH -Body ('{"event_id":1,"class_id":' + $cid + '}')
    Write-Output "compute class ${cid}: $($r.computed)/$($r.students)"
}

# Tabulation summary
foreach ($cid in @(1, 10)) {
    $t = Invoke-RestMethod "$base/results/tabulation?event_id=1&class_id=$cid" -Headers $AH
    Write-Output "--- TABULATION class $cid (subjects: $($t.subjects.Count)) ---"
    $t.rows | ForEach-Object { Write-Output ("  roll {0} {1} GPA:{2} [{3}] pos:{4}" -f $_.roll, $_.name, $_.final_gpa, $_.result_status, $_.position) }
}