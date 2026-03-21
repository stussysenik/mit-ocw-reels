#!/usr/bin/env python3
"""
O(1) MIT OCW catalogue fetcher.

Two data sources, fetched independently, joined in memory:
  Source A: MIT Learn API  — 3 paginated requests → ~290 courses (metadata)
  Source B: Kaggle dataset — 1 download → ~5,000 video records (YouTube IDs)

Total HTTP requests: ~4, constant regardless of catalogue size.

Usage:
  python3 tools/fetch_ocw.py                  # full run
  python3 tools/fetch_ocw.py --limit 5        # test with 5 courses
  python3 tools/fetch_ocw.py --force          # bypass cache
  python3 tools/fetch_ocw.py --dry-run        # fetch + report stats, don't write
"""

import argparse
import csv
import io
import json
import os
import re
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CACHE_DIR = SCRIPT_DIR / ".cache"
OUTPUT_PATH = SCRIPT_DIR.parent / "MITReels" / "Resources" / "seed_data.json"

MIT_LEARN_API = "https://api.learn.mit.edu/api/v1/courses/"
KAGGLE_DATASET_URL = (
    "https://www.kaggle.com/api/v1/datasets/download"
    "/jorgoose/mit-opencourseware-youtube-course-data"
)

CACHE_TTL = 86400  # 24 hours in seconds


def cache_path(name: str) -> Path:
    return CACHE_DIR / name


def is_cache_valid(path: Path) -> bool:
    if not path.exists():
        return False
    age = time.time() - path.stat().st_mtime
    return age < CACHE_TTL


def fetch_url(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "MITReels/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8")


# ---------------------------------------------------------------------------
# Source A: MIT Learn API
# ---------------------------------------------------------------------------

def fetch_mit_learn_api(force: bool = False) -> list[dict]:
    """Fetch all OCW courses with lecture videos via paginated API."""
    cached = cache_path("mit_learn_api.json")
    if not force and is_cache_valid(cached):
        print(f"  Using cached MIT Learn API data ({cached})")
        with open(cached) as f:
            return json.load(f)

    print("  Fetching MIT Learn API...")
    all_courses = []
    offset = 0
    limit = 100

    while True:
        url = (
            f"{MIT_LEARN_API}?platform=ocw"
            f"&course_feature=Lecture+Videos&limit={limit}&offset={offset}"
        )
        print(f"    GET offset={offset}...")
        raw = fetch_url(url)
        data = json.loads(raw)
        results = data.get("results", [])
        if not results:
            break
        all_courses.extend(results)
        offset += limit
        if offset >= data.get("count", 0):
            break

    print(f"  Fetched {len(all_courses)} courses from MIT Learn API")

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with open(cached, "w") as f:
        json.dump(all_courses, f)

    return all_courses


def parse_api_course(raw: dict) -> dict | None:
    """Extract structured course metadata from an API record."""
    readable_id = raw.get("readable_id", "")
    title = raw.get("title", "")
    if not readable_id or not title:
        return None

    # Extract course number from readable_id (e.g., "18.06+spring_2010" → "18.06")
    course_number = readable_id.split("+")[0].upper().replace("_", ".")

    departments = raw.get("departments", [])
    department = departments[0].get("name", "") if departments else ""

    runs = raw.get("runs", [])
    semester = ""
    year = 0
    if runs:
        run = runs[0]
        semester = run.get("semester", "") or ""
        year = run.get("year") or 0

    topics = raw.get("topics", [])
    topic_name = topics[0].get("name", "") if topics else ""

    url = raw.get("url", "")

    return {
        "courseNumber": course_number,
        "title": title,
        "department": department,
        "semester": semester,
        "year": year,
        "topicName": topic_name,
        "url": url,
    }


# ---------------------------------------------------------------------------
# Source B: Kaggle CSV (YouTube video mapping)
# ---------------------------------------------------------------------------

def fetch_kaggle_csv(force: bool = False) -> list[dict]:
    """Download the Kaggle dataset ZIP and extract the CSV with YouTube video mappings.

    The Kaggle dataset (jorgoose/mit-opencourseware-youtube-course-data) bundles
    the CSV inside a ZIP archive.  The CSV filename contains a timestamp
    (e.g. mit_courses_2025-02-26_010109.csv), so we find it by extension.
    """
    cached = cache_path("kaggle_videos.csv")
    if not force and is_cache_valid(cached):
        print(f"  Using cached Kaggle CSV ({cached})")
        with open(cached) as f:
            return list(csv.DictReader(f))

    print("  Fetching Kaggle dataset ZIP...")
    req = urllib.request.Request(
        KAGGLE_DATASET_URL, headers={"User-Agent": "MITReels/1.0"}
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        zip_bytes = resp.read()
    print(f"  Downloaded {len(zip_bytes)} bytes")

    # Extract the CSV from the ZIP
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        csv_names = [n for n in zf.namelist() if n.endswith(".csv")]
        if not csv_names:
            raise RuntimeError(
                f"No CSV found in Kaggle ZIP. Contents: {zf.namelist()}"
            )
        csv_name = csv_names[0]
        print(f"  Extracting {csv_name} from ZIP...")
        raw = zf.read(csv_name).decode("utf-8")

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with open(cached, "w") as f:
        f.write(raw)

    return list(csv.DictReader(io.StringIO(raw)))


def extract_youtube_id(url: str) -> str | None:
    """Extract YouTube video ID from a URL."""
    patterns = [
        r"(?:v=|/v/|youtu\.be/|/embed/)([a-zA-Z0-9_-]{11})",
        r"^([a-zA-Z0-9_-]{11})$",
    ]
    for pattern in patterns:
        m = re.search(pattern, url)
        if m:
            return m.group(1)
    return None


def extract_course_number_from_title(title: str) -> str | None:
    """Try to extract a course number like '18.06' from a title."""
    # Match patterns like "18.06", "6.003", "14.41", "RES.10-001"
    m = re.search(r"\b((?:RES\.)?[\d]+\.[\w.-]+)\b", title, re.IGNORECASE)
    if m:
        return m.group(1).upper()
    return None


# ---------------------------------------------------------------------------
# Normalize + Join
# ---------------------------------------------------------------------------

def normalize_title(title: str) -> str:
    """Normalize a title for fuzzy matching."""
    title = title.lower()
    # Remove semester/year info
    title = re.sub(r"\b(spring|fall|summer|january|iap)\s*\d{4}\b", "", title)
    # Remove parenthetical course numbers
    title = re.sub(r"\([^)]*\)", "", title)
    # Remove special chars, collapse whitespace
    title = re.sub(r"[^a-z0-9\s]", " ", title)
    title = re.sub(r"\s+", " ", title).strip()
    return title


def join_data(api_courses: list[dict], kaggle_rows: list[dict], limit: int | None = None) -> dict:
    """Join MIT Learn API course metadata with Kaggle YouTube video data."""

    # Parse API courses
    parsed_courses = {}
    course_by_normalized_title = {}
    for raw in api_courses:
        course = parse_api_course(raw)
        if course:
            cn = course["courseNumber"]
            parsed_courses[cn] = course
            norm = normalize_title(course["title"])
            course_by_normalized_title[norm] = course

    print(f"  Parsed {len(parsed_courses)} API courses")

    # Group Kaggle rows by course title
    kaggle_by_course: dict[str, list[dict]] = {}
    for row in kaggle_rows:
        course_title = row.get("CourseTitle", "").strip()
        if course_title:
            kaggle_by_course.setdefault(course_title, []).append(row)

    print(f"  Found {len(kaggle_by_course)} unique courses in Kaggle data")

    # Build output
    output_courses: dict[str, dict] = {}
    output_lectures: list[dict] = []
    matched_count = 0
    unmatched_count = 0

    course_titles = list(kaggle_by_course.keys())
    if limit:
        course_titles = course_titles[:limit]

    for kaggle_title in course_titles:
        rows = kaggle_by_course[kaggle_title]
        matched_course = None

        # Strategy 1: Extract course number from Kaggle title
        cn = extract_course_number_from_title(kaggle_title)
        if cn and cn in parsed_courses:
            matched_course = parsed_courses[cn]

        # Strategy 2: Normalized title match
        if not matched_course:
            norm = normalize_title(kaggle_title)
            if norm in course_by_normalized_title:
                matched_course = course_by_normalized_title[norm]

        # Strategy 3: Partial match — find best overlap
        if not matched_course:
            norm = normalize_title(kaggle_title)
            norm_words = set(norm.split())
            best_score = 0
            for api_norm, api_course in course_by_normalized_title.items():
                api_words = set(api_norm.split())
                if not api_words:
                    continue
                overlap = len(norm_words & api_words) / max(len(norm_words), len(api_words))
                if overlap > best_score and overlap > 0.5:
                    best_score = overlap
                    matched_course = api_course

        if matched_course:
            matched_count += 1
            course_number = matched_course["courseNumber"]
            department = matched_course["department"]
            semester = matched_course["semester"]
            year = matched_course["year"]
            topic_name = matched_course["topicName"]
            ocw_url = matched_course.get("url", "")
        else:
            unmatched_count += 1
            # Best-effort from Kaggle data
            course_number = cn or ""
            taxonomy = rows[0].get("Taxonomy", "")
            department = taxonomy.split(">")[0].strip() if taxonomy else ""
            topic_name = taxonomy.split(">")[-1].strip() if taxonomy else ""
            semester = ""
            year = 0
            ocw_url = ""

        if not course_number:
            # Generate a course number from the title
            course_number = re.sub(r"[^A-Za-z0-9]", "", kaggle_title[:20]).upper()

        # Add course
        if course_number not in output_courses:
            output_courses[course_number] = {
                "courseNumber": course_number,
                "title": matched_course["title"] if matched_course else kaggle_title,
                "department": department,
                "semester": semester,
                "year": year,
                "source": "mit-ocw",
            }

        # Add lectures from this course
        for row in rows:
            video_url = row.get("VideoURL", "")
            youtube_id = extract_youtube_id(video_url)
            if not youtube_id:
                continue

            position = 0
            pos_str = row.get("Position", "0")
            try:
                position = int(pos_str)
            except (ValueError, TypeError):
                pass

            video_title = row.get("VideoTitle", "").strip()
            if not video_title:
                continue

            course_data = output_courses[course_number]
            output_lectures.append({
                "title": video_title,
                "youtubeId": youtube_id,
                "courseNumber": course_number,
                "courseName": course_data["title"],
                "department": course_data["department"],
                "semester": course_data["semester"],
                "year": course_data["year"],
                "ocwUrl": ocw_url,
                "topicName": topic_name,
                "lectureNumber": position,
                "source": "mit-ocw",
            })

    print(f"  Matched: {matched_count}, Unmatched: {unmatched_count}")
    print(f"  Total courses: {len(output_courses)}, Total lectures: {len(output_lectures)}")

    return {
        "seedVersion": 2,
        "sources": [
            {"id": "mit-ocw", "name": "MIT OpenCourseWare", "enabled": True}
        ],
        "courses": sorted(output_courses.values(), key=lambda c: c["courseNumber"]),
        "lectures": output_lectures,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Fetch MIT OCW catalogue")
    parser.add_argument("--limit", type=int, help="Limit to N courses (for testing)")
    parser.add_argument("--force", action="store_true", help="Bypass cache")
    parser.add_argument("--dry-run", action="store_true", help="Fetch + stats, don't write")
    args = parser.parse_args()

    print("=== MIT OCW Catalogue Fetcher ===\n")

    print("[1/3] Fetching course metadata (MIT Learn API)...")
    api_courses = fetch_mit_learn_api(force=args.force)

    print("\n[2/3] Fetching YouTube video mapping (Kaggle CSV)...")
    kaggle_rows = fetch_kaggle_csv(force=args.force)

    print(f"\n[3/3] Joining data (limit={args.limit or 'all'})...")
    result = join_data(api_courses, kaggle_rows, limit=args.limit)

    print(f"\n=== Results ===")
    print(f"  Seed version: {result['seedVersion']}")
    print(f"  Courses: {len(result['courses'])}")
    print(f"  Lectures: {len(result['lectures'])}")

    # Show department breakdown
    dept_counts: dict[str, int] = {}
    for course in result["courses"]:
        dept = course["department"] or "Unknown"
        dept_counts[dept] = dept_counts.get(dept, 0) + 1
    print(f"\n  Departments ({len(dept_counts)}):")
    for dept, count in sorted(dept_counts.items(), key=lambda x: -x[1])[:10]:
        print(f"    {dept}: {count} courses")
    if len(dept_counts) > 10:
        print(f"    ... and {len(dept_counts) - 10} more")

    if args.dry_run:
        print("\n  [DRY RUN] Skipping file write.")
        return

    # Write output
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    print(f"\n  Written to {OUTPUT_PATH}")
    print(f"  File size: {OUTPUT_PATH.stat().st_size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
