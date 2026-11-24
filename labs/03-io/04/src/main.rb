require 'date'

DATA_FILE = File.join(__dir__, 'expenses.txt')

def input(prompt)
  print prompt
  STDIN.gets&.strip
end

def valid_date?(value)
  return false unless value && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
  Date.iso8601(value)
  true
rescue Date::Error
  false
end

def parse_amount(value)
  return nil unless value && value.match?(/\A\d+(?:[.,]\d{1,2})?\z/)
  whole, fraction = value.tr(',', '.').split('.', 2)
  cents = whole.to_i * 100 + (fraction || '0').ljust(2, '0').to_i
  cents.positive? ? cents : nil
end

def money(cents)
  format('%d.%02d', cents / 100, cents % 100)
end

def valid_text?(text)
  text && !text.empty? && !text.include?('|')
end

def load_expenses(path)
  return [] unless File.exist?(path)

  File.readlines(path, encoding: 'UTF-8').filter_map do |line|
    parts = line.chomp.split('|', -1)
    next unless parts.length == 5

    id, date, category, amount, note = parts
    next unless id.match?(/\A\d+\z/) && amount.match?(/\A\d+\z/)

    {
      id: id.to_i,
      date: date,
      category: category,
      cents: amount.to_i,
      note: note
    }
  end
end

def save_expenses(expenses, path)
  File.open(path, 'w:UTF-8') do |file|
    expenses.each do |e|
      file.puts [
        e[:id], e[:date], e[:category],
        e[:cents], e[:note]
      ].join('|')
    end
  end
end

def show_expenses(expenses)
  if expenses.empty?
    puts 'No expenses found.'
    return
  end

  puts 'ID | Date | Category | Amount | Description'

  expenses.sort_by { |e| [e[:date], e[:id]] }.each do |e|
    puts "#{e[:id]} | #{e[:date]} | #{e[:category]} | #{money(e[:cents])} | #{e[:note]}"
  end
end

def add_expense(expenses)
  date = input('Date (YYYY-MM-DD): ')

  unless valid_date?(date)
    puts 'Invalid date.'
    return
  end

  category = input('Category: ')

  unless valid_text?(category)
    puts 'Invalid category.'
    return
  end

  amount = parse_amount(input('Amount: '))

  unless amount
    puts 'Amount must be positive (e.g. 120.50).'
    return
  end

  note = input('Description: ')

  if note.nil? || note.include?('|')
    puts 'Invalid description.'
    return
  end

  id = (expenses.map { |e| e[:id] }.max || 0) + 1

  expenses << {
    id: id,
    date: date,
    category: category,
    cents: amount,
    note: note
  }

  save_expenses(expenses, DATA_FILE)
  puts "Expense ##{id} saved."
end

def edit_expense(expenses)
  id = input('ID to edit: ')
  expense = expenses.find { |e| e[:id].to_s == id }

  unless expense
    puts 'Expense not found.'
    return
  end

  puts 'Press Enter to keep the current value.'

  date = input("Date [#{expense[:date]}]: ")
  category = input("Category [#{expense[:category]}]: ")
  amount = input("Amount [#{money(expense[:cents])}]: ")
  note = input("Description [#{expense[:note]}]: ")

  return if [date, category, amount, note].any?(&:nil?)

  if (!date.empty? && !valid_date?(date)) ||
     (!category.empty? && !valid_text?(category)) ||
     (!amount.empty? && !parse_amount(amount)) ||
     note.include?('|')
    puts 'Invalid value. No changes saved.'
    return
  end

  expense[:date] = date unless date.empty?
  expense[:category] = category unless category.empty?
  expense[:cents] = parse_amount(amount) unless amount.empty?
  expense[:note] = note unless note.empty?

  save_expenses(expenses, DATA_FILE)
  puts 'Expense updated.'
end

def delete_expense(expenses)
  id = input('ID to delete: ')
  expense = expenses.find { |e| e[:id].to_s == id }

  unless expense
    puts 'Expense not found.'
    return
  end

  expenses.delete(expense)
  save_expenses(expenses, DATA_FILE)
  puts 'Expense deleted.'
end

def show_summary(expenses)
  total = expenses.sum { |e| e[:cents] }

  puts "Total: #{money(total)}"
  puts "Number of expenses: #{expenses.length}"

  expenses.group_by { |e| e[:category] }.sort.each do |category, items|
    sum = items.sum { |e| e[:cents] }
    puts "#{category}: #{money(sum)}"
  end
end

def run_tests
  examples = [
    { id: 1, date: '2026-10-01', category: 'Food', cents: 1250, note: 'Lunch' },
    { id: 2, date: '2026-10-02', category: 'Travel', cents: 3000, note: 'Bus' },
    { id: 3, date: '2026-10-03', category: 'Food', cents: 875, note: 'Coffee' }
  ]

  test_file = File.join(__dir__, 'expenses_test.txt')
  save_expenses(examples, test_file)

  checks = {
    'Save and load' => load_expenses(test_file) == examples,
    'Decimal amount' => parse_amount('12.50') == 1250,
    'Comma amount' => parse_amount('12,5') == 1250,
    'Invalid amount' => parse_amount('-2') == nil && parse_amount('0') == nil,
    'Invalid date' => !valid_date?('2026-02-30'),
    'Total' => examples.sum { |e| e[:cents] } == 5125,
    'Category sum' => examples.select { |e| e[:category] == 'Food' }.sum { |e| e[:cents] } == 2125
  }

  checks.each do |name, passed|
    puts "#{name}: #{passed ? 'PASS' : 'FAIL'}"
  end
ensure
  File.delete(test_file) if test_file && File.exist?(test_file)
end

File.write(DATA_FILE, '', mode: 'w', encoding: 'UTF-8') unless File.exist?(DATA_FILE)
expenses = load_expenses(DATA_FILE)

loop do
  puts "\n1 - Add expense"
  puts '2 - Show all expenses'
  puts '3 - Edit expense'
  puts '4 - Delete expense'
  puts '5 - Summary by category'
  puts '6 - Search by category'
  puts '7 - Run tests'
  puts '0 - Exit'

  choice = input('Choose: ')

  case choice
  when '1'
    add_expense(expenses)
  when '2'
    show_expenses(expenses)
  when '3'
    edit_expense(expenses)
  when '4'
    delete_expense(expenses)
  when '5'
    show_summary(expenses)
  when '6'
    category = input('Category to search: ')
    show_expenses(expenses.select { |e| e[:category].casecmp?(category.to_s) })
  when '7'
    run_tests
  when '0', nil
    break
  else
    puts 'Unknown command.'
  end
end
