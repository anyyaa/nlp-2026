(define (create-file)
  (call-with-output-file "students.txt"
    (lambda (port)
      (display "Anna 95\n" port)
      (display "Boris 54\n" port)
      (display "Vera 88\n" port)
      (display "Gleb 60\n" port)
      (display "Diana 41\n" port)
      (display "Egor 70\n" port))))

(define (analyze-file filename)
  (call-with-input-file filename
    (lambda (port)
      (let loop ((count 0)
                 (total 0)
                 (minimum 101)
                 (maximum -1)
                 (passed 0))
        (let ((name (read port)))
          (if (eof-object? name)
              (if (= count 0)
                  (list 0 0 0 0 0)
                  (list count
                        (/ (* 1.0 total) count)
                        minimum
                        maximum
                        passed))
              (let ((score (read port)))
                (loop (+ count 1)
                      (+ total score)
                      (min minimum score)
                      (max maximum score)
                      (if (>= score 60)
                          (+ passed 1)
                          passed)))))))))

(define (print-report stats port)
  (display "=== Exam Results ===\n" port)

  (display "Total students: " port)
  (display (list-ref stats 0) port)
  (newline port)

  (display "Average score: " port)
  (display (list-ref stats 1) port)
  (newline port)

  (display "Minimum score: " port)
  (display (list-ref stats 2) port)
  (newline port)

  (display "Maximum score: " port)
  (display (list-ref stats 3) port)
  (newline port)

  (display "Passed students: " port)
  (display (list-ref stats 4) port)
  (newline port)

  (display "Failed students: " port)
  (display (- (list-ref stats 0)
              (list-ref stats 4)) port)
  (newline port))

(define (main)
  (create-file)

  (let ((stats (analyze-file "students.txt")))
    (call-with-output-file "report.txt"
      (lambda (port)
        (print-report stats port)))

    (display "Students file created: students.txt")
    (newline)
    (display "Report saved to report.txt")
    (newline)))

(main)
