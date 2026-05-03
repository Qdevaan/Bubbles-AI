"""Remove orphaned stale lines 256-284 from brain_service.py."""
path = 'server_v2/app/services/brain_service.py'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

# Lines are 1-indexed; remove lines 256 to 284 inclusive (0-indexed: 255 to 283)
del lines[255:284]

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f"Done. File now has {len(lines)} lines.")
# Print lines 253-265 to verify
for i, l in enumerate(lines[252:265], start=253):
    print(f"{i}: {repr(l)}")
