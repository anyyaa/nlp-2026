(ns csv-to-xml
  (:require [clojure.string :as str]))

(defn parse-csv [raw]
  (let [raw (if (str/starts-with? raw "\uFEFF") (subs raw 1) raw)
        text (str/replace raw #"\r\n?" "\n")
        length (count text)]
    (loop [index 0
           state :start
           field (StringBuilder.)
           row []
           rows []]
      (if (= index length)
        (cond
          (= state :quoted)
          (throw (ex-info "Unclosed quoted field" {:position (inc index)}))

          (and (= state :start) (empty? row))
          rows

          :else
          (conj rows (conj row (.toString field))))
        (let [ch (.charAt text index)]
          (case state
            :quoted
            (if (= ch \")
              (if (and (< (inc index) length)
                       (= (.charAt text (inc index)) \"))
                (do
                  (.append field \")
                  (recur (+ index 2) :quoted field row rows))
                (recur (inc index) :closed field row rows))
              (do
                (.append field ch)
                (recur (inc index) :quoted field row rows)))

            :closed
            (cond
              (= ch \,)
              (recur (inc index) :start (StringBuilder.)
                     (conj row (.toString field)) rows)

              (= ch \newline)
              (recur (inc index) :start (StringBuilder.) []
                     (conj rows (conj row (.toString field))))

              :else
              (throw (ex-info "Unexpected character after closing quote"
                              {:position (inc index)})))

            :start
            (cond
              (= ch \")
              (recur (inc index) :quoted field row rows)

              (= ch \,)
              (recur (inc index) :start (StringBuilder.) (conj row "") rows)

              (= ch \newline)
              (recur (inc index) :start (StringBuilder.) []
                     (conj rows (conj row "")))

              :else
              (do
                (.append field ch)
                (recur (inc index) :plain field row rows)))

            :plain
            (cond
              (= ch \,)
              (recur (inc index) :start (StringBuilder.)
                     (conj row (.toString field)) rows)

              (= ch \newline)
              (recur (inc index) :start (StringBuilder.) []
                     (conj rows (conj row (.toString field))))

              (= ch \")
              (throw (ex-info "Quote inside an unquoted field"
                              {:position (inc index)}))

              :else
              (do
                (.append field ch)
                (recur (inc index) :plain field row rows)))))))))

(defn xml-tag [index header]
  (when (str/blank? header)
    (throw (ex-info "Empty CSV header" {:column (inc index)})))
  (let [cleaned (-> header
                    str/trim
                    (str/replace #"[^\p{L}\p{N}_.-]" "_"))]
    (if (re-find #"^[\p{L}_]" cleaned)
      cleaned
      (str "field_" cleaned))))

(defn xml-escape [value]
  (when (some (fn [ch]
                (let [n (int ch)]
                  (and (< n 32) (not (#{9 10 13} n)))))
              value)
    (throw (ex-info "Invalid control character in XML data" {})))
  (-> value
      (str/replace "&" "&amp;")
      (str/replace "<" "&lt;")
      (str/replace ">" "&gt;")
      (str/replace "\"" "&quot;")
      (str/replace "'" "&apos;")))

(defn csv-to-xml [csv]
  (let [rows (parse-csv csv)]
    (when (empty? rows)
      (throw (ex-info "CSV file is empty" {})))
    (let [headers (first rows)
          tags (vec (map-indexed xml-tag headers))
          data (rest rows)
          columns (count tags)]
      (when (not= columns (count (distinct tags)))
        (throw (ex-info "Duplicate XML field names" {})))
      (doseq [[index row] (map-indexed vector data)]
        (when (not= (count row) columns)
          (throw (ex-info "Wrong number of fields"
                          {:row (+ index 2)
                           :expected columns
                           :actual (count row)}))))
      (str "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
           "<records>\n"
           (apply str
                  (for [row data]
                    (str "  <record>\n"
                         (apply str
                                (map (fn [tag value]
                                       (str "    <" tag ">"
                                            (xml-escape value)
                                            "</" tag ">\n"))
                                     tags row))
                         "  </record>\n")))
           "</records>\n"))))

(defn convert-file [input-file output-file]
  (let [xml (csv-to-xml (slurp input-file :encoding "UTF-8"))]
    (spit output-file xml :encoding "UTF-8")
    xml))

(defn fails? [input]
  (try
    (csv-to-xml input)
    false
    (catch clojure.lang.ExceptionInfo _ true)))

(defn run-tests []
  (let [tests
        [["Simple conversion"
          (fn [] (str/includes? (csv-to-xml "name,age\nAnna,21\n")
                                "<age>21</age>"))]
         ["Quoted comma"
          (fn [] (str/includes? (csv-to-xml "item,note\nTea,\"milk, sugar\"\n")
                                "<note>milk, sugar</note>"))]
         ["Escaped CSV quotes"
          (fn [] (str/includes? (csv-to-xml "name\n\"Vera \"\"V\"\"\"\n")
                                "<name>Vera &quot;V&quot;</name>"))]
         ["XML escaping"
          (fn [] (str/includes? (csv-to-xml "text\n\"&<>\"\"'\"\n")
                                "&amp;&lt;&gt;&quot;&apos;"))]
         ["Multiline field"
          (fn [] (str/includes? (csv-to-xml "note\n\"first\nsecond\"\n")
                                "<note>first\nsecond</note>"))]
         ["Windows line endings and BOM"
          (fn [] (str/includes? (csv-to-xml "\uFEFFname,age\r\nAnna,21\r\n")
                                "<name>Anna</name>"))]
         ["Header normalization"
          (fn [] (str/includes? (csv-to-xml "first name,2score\nAnna,10\n")
                                "<field_2score>10</field_2score>"))]
         ["Trailing empty field"
          (fn [] (str/includes? (csv-to-xml "name,note\nAnna,\n")
                                "<note></note>"))]
         ["Empty file rejected"
          (fn [] (fails? ""))]
         ["Missing column rejected"
          (fn [] (fails? "a,b\n1\n"))]
         ["Extra column rejected"
          (fn [] (fails? "a,b\n1,2,3\n"))]
         ["Unclosed quote rejected"
          (fn [] (fails? "name\n\"unfinished\n"))]
         ["Unexpected quote rejected"
          (fn [] (fails? "name\nA\"B\n"))]
         ["Duplicate headers rejected"
          (fn [] (fails? "first name,first_name\na,b\n"))]
         ["File input and output"
          (fn []
            (let [source (java.io.File/createTempFile "csv-xml-in-" ".csv")
                  target (java.io.File/createTempFile "csv-xml-out-" ".xml")]
              (try
                (spit source "name,age\nAnna,21\n" :encoding "UTF-8")
                (convert-file (.getAbsolutePath source)
                              (.getAbsolutePath target))
                (str/includes? (slurp target :encoding "UTF-8")
                               "<name>Anna</name>")
                (finally
                  (.delete source)
                  (.delete target)))))]]
        outcomes (mapv (fn [[name check]]
                         (let [ok (try
                                    (boolean (check))
                                    (catch Exception _ false))]
                           (println (str name ": " (if ok "PASS" "FAIL")))
                           ok))
                       tests)
        passed (count (filter true? outcomes))]
    (println)
    (println (str "Passed: " passed "/" (count tests)))
    (when (not= passed (count tests))
      (System/exit 1))))

(defn -main [& args]
  (try
    (if (= (first args) "--test")
      (run-tests)
      (let [[input output & extra] args]
        (when (seq extra)
          (throw (ex-info "Too many arguments" {})))
        (let [input (or input "input.csv")
              output (or output "output.xml")
              xml (convert-file input output)
              records (count (rest (parse-csv (slurp input :encoding "UTF-8"))))]
          (println (str "Input file: " input))
          (println (str "Records converted: " records))
          (println (str "XML saved to: " output)))))
    (catch Exception e
      (binding [*out* *err*]
        (println (str "Error: " (.getMessage e))))
      (System/exit 1))))

(apply -main *command-line-args*)
