(defparameter *input-file* "matrix.txt")
(defparameter *output-file* "result.txt")

(defun read-required-integer (stream label)
  (let ((value (read stream nil :end-of-file)))
    (unless (integerp value)
      (error "Expected an integer for ~A." label))
    value))

(defun read-matrix-from-stream (stream)
  (let* ((*read-eval* nil)
         (rows (read-required-integer stream "row count"))
         (cols (read-required-integer stream "column count")))
    (unless (and (> rows 0) (> cols 0))
      (error "Matrix dimensions must be positive."))
    (let ((matrix (make-array (list rows cols)))
          (end-marker (gensym)))
      (dotimes (i rows)
        (dotimes (j cols)
          (setf (aref matrix i j)
                (read-required-integer stream "matrix element"))))
      (unless (eq (read stream nil end-marker) end-marker)
        (error "Unexpected extra data after the matrix."))
      (values matrix rows cols))))

(defun read-matrix (filename)
  (with-open-file (input filename :direction :input)
    (read-matrix-from-stream input)))

(defun analyze-matrix (matrix rows cols)
  (let ((row-sums (make-array rows :initial-element 0))
        (column-sums (make-array cols :initial-element 0))
        (row-maxima (make-array rows)))
    (dotimes (i rows)
      (setf (aref row-maxima i) (aref matrix i 0))
      (dotimes (j cols)
        (let ((value (aref matrix i j)))
          (incf (aref row-sums i) value)
          (incf (aref column-sums j) value)
          (when (> value (aref row-maxima i))
            (setf (aref row-maxima i) value)))))
    (values row-sums column-sums row-maxima)))

(defun write-report (stream matrix rows cols row-sums column-sums row-maxima)
  (format stream "=== Matrix Analysis ===~%")
  (format stream "Rows: ~D~%" rows)
  (format stream "Columns: ~D~%~%" cols)
  (format stream "Input matrix:~%")
  (dotimes (i rows)
    (dotimes (j cols)
      (when (> j 0)
        (write-char #\Space stream))
      (princ (aref matrix i j) stream))
    (terpri stream))
  (format stream "~%Row statistics:~%")
  (dotimes (i rows)
    (format stream "Row ~D: sum = ~D, max = ~D~%"
            (1+ i) (aref row-sums i) (aref row-maxima i)))
  (format stream "~%Column statistics:~%")
  (dotimes (j cols)
    (format stream "Column ~D: sum = ~D~%"
            (1+ j) (aref column-sums j))))

(defun process-matrix ()
  (multiple-value-bind (matrix rows cols)
      (read-matrix *input-file*)
    (multiple-value-bind (row-sums column-sums row-maxima)
        (analyze-matrix matrix rows cols)
      (with-open-file (output *output-file*
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-report output matrix rows cols
                      row-sums column-sums row-maxima))
      (format t "Matrix: ~D x ~D~%" rows cols)
      (format t "Row sums: ~{~D~^, ~}~%" (coerce row-sums 'list))
      (format t "Column sums: ~{~D~^, ~}~%" (coerce column-sums 'list))
      (format t "Row maxima: ~{~D~^, ~}~%" (coerce row-maxima 'list))
      (format t "Report saved to ~A~%" *output-file*))))

(defun input-causes-error-p (text)
  (handler-case
      (with-input-from-string (input text)
        (read-matrix-from-stream input)
        nil)
    (error () t)))

(defun run-tests ()
  (let ((passed 0)
        (total 0))
    (flet ((check (name condition)
             (incf total)
             (when condition (incf passed))
             (format t "~A: ~A~%" name (if condition "PASS" "FAIL"))))
      (with-input-from-string
          (input "3 4 1 2 3 4 5 6 7 8 9 10 11 12")
        (multiple-value-bind (matrix rows cols)
            (read-matrix-from-stream input)
          (multiple-value-bind (row-sums column-sums maxima)
              (analyze-matrix matrix rows cols)
            (check "Matrix dimensions" (and (= rows 3) (= cols 4)))
            (check "Row sums" (equalp row-sums #(10 26 42)))
            (check "Column sums" (equalp column-sums #(15 18 21 24)))
            (check "Row maxima" (equalp maxima #(4 8 12)))
            (let ((report
                    (with-output-to-string (output)
                      (write-report output matrix rows cols
                                    row-sums column-sums maxima))))
              (check "Report includes rows"
                     (not (null (search "Row 3: sum = 42, max = 12" report))))
              (check "Report includes columns"
                     (not (null (search "Column 4: sum = 24" report))))))))
      (with-input-from-string
          (input "2 3 -5 -2 -9 4 0 -1")
        (multiple-value-bind (matrix rows cols)
            (read-matrix-from-stream input)
          (multiple-value-bind (row-sums column-sums maxima)
              (analyze-matrix matrix rows cols)
            (check "Negative values: row sums"
                   (equalp row-sums #(-16 3)))
            (check "Negative values: column sums"
                   (equalp column-sums #(-1 -2 -10)))
            (check "Negative values: maxima"
                   (equalp maxima #(-2 4))))))
      (with-input-from-string (input "1 1 -8")
        (multiple-value-bind (matrix rows cols)
            (read-matrix-from-stream input)
          (multiple-value-bind (row-sums column-sums maxima)
              (analyze-matrix matrix rows cols)
            (check "Single-element matrix"
                   (and (= (aref row-sums 0) -8)
                        (= (aref column-sums 0) -8)
                        (= (aref maxima 0) -8))))))
      (check "Zero dimension rejected"
             (input-causes-error-p "0 3"))
      (check "Missing element rejected"
             (input-causes-error-p "2 2 1 2 3"))
      (check "Extra element rejected"
             (input-causes-error-p "1 1 5 6"))
      (check "Non-integer rejected"
             (input-causes-error-p "1 2 3 abc"))
      (check "Empty input rejected"
             (input-causes-error-p "")))
    (format t "~%Passed: ~D/~D~%" passed total)
    (= passed total)))

(handler-case
    (if (member "--test" sb-ext:*posix-argv* :test #'string=)
        (unless (run-tests)
          (sb-ext:exit :code 1))
        (process-matrix))
  (error (condition)
    (format *error-output* "Error: ~A~%" condition)
    (sb-ext:exit :code 1)))
