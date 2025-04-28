#!/usr/bin/env python3

def read_urls_from_file(file_path):
    try:
        with open(file_path, 'r') as file:
            return set(line.strip() for line in file if line.strip())
    except FileNotFoundError:
        print(f"Warning: File {file_path} not found.")
        return set()

# Read URLs from all files
core_urls = read_urls_from_file('./core/clone_urls.txt')
extra_urls = read_urls_from_file('./extra/clone_urls.txt')
processed_urls = read_urls_from_file('processed_urls.txt')

# Combine core and extra URLs
combined_urls = core_urls.union(extra_urls)

# Find URLs in combined set but not in processed
missing_urls = combined_urls - processed_urls

# Save results to file
with open('missing_urls.txt', 'w') as output_file:
    for url in sorted(missing_urls):
        output_file.write(f"{url}\n")

# Display results
print(f"URLs present in source files but missing from processed_url.txt: {len(missing_urls)}")
if missing_urls:
    print("\nMissing URLs:")
    for url in sorted(missing_urls):
        print(url)
    print(f"\nResults saved to missing_urls.txt")
else:
    print("No missing URLs found.")
