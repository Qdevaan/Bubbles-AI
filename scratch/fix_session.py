"""Remove the unused _buildAdviceContent method from new_session_screen.dart (lines 1166-1292)."""
path = 'lib/screens/new_session_screen.dart'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")
print(f"Line 1165: {repr(lines[1164])}")
print(f"Line 1166: {repr(lines[1165])}")
print(f"Line 1292: {repr(lines[1291])}")
print(f"Line 1293: {repr(lines[1292])}")

# Remove lines 1166-1292 inclusive (0-indexed: 1165-1291)
new_lines = lines[:1165] + lines[1292:]

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(f"Done. New total lines: {len(new_lines)}")
