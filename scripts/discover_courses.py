#!/usr/bin/env python3
"""
YouTube API Course Discovery Script

Fetches ALL playlists from each university's YouTube channel,
then fetches first 3 videos from each playlist (course-like playlists only).
Outputs multi_source_seed.json for the MIT Reels app.

Usage:
  python3 scripts/discover_courses.py YOUR_YOUTUBE_API_KEY
"""

import json
import sys
import urllib.request
import urllib.parse
import time

API_BASE = "https://www.googleapis.com/youtube/v3"

# Channel registry: (sourceId, displayName, channelId)
CHANNELS = [
    ("stanford", "Stanford Online", "UCBa5G_ESCn8Uf67UGNEbXvA"),
    ("stanford", "Stanford Engineering", "UCddiUEpeqJcYeBxX1IVBKvQ"),
    ("harvard", "Harvard University", "UCT75CAoariMJGYEM-NTox9A"),
    ("harvard", "Harvard CS50", "UCcabW7890RKJzL968QWEykA"),
    ("yale", "YaleCourses", "UC4EY_qnSeAP1xGsh61eASoA"),
    ("caltech", "Caltech", "UCXIFkVnqEbEBHtEjiqHCaJQ"),
    ("berkeley", "UC Berkeley", "UCEVLABSfx4GqYzzFMJKjpPg"),
    ("cmu", "Carnegie Mellon CS", "UCOWzl3JZ3q8CkNdNgumEcXw"),
    ("cmu", "CMU Database Group", "UCHnBsf2rH-K7pn09rb3qvkA"),
    ("princeton", "Princeton", "UCirGJHNBb0kXnU1FvKnNF0A"),
    ("cornell", "Cornell Engineering", "UCnrAMLVfcRAO0PVXOOzx4NA"),
    ("3blue1brown", "3Blue1Brown", "UCYO_jab_esuFRV4b17AJtAw"),
    ("khan_academy", "Khan Academy", "UC4a-Gbdw7vOaccHmFo40b9g"),
    ("crash_course", "CrashCourse", "UCX6b17PVsYBQ0ip5gyeme-Q"),
]

# Department inference from playlist title keywords
DEPT_KEYWORDS = {
    "Computer Science": ["cs", "programming", "algorithm", "data structure", "software", "computer", "code", "python", "java", "machine learning", "artificial intelligence", "deep learning", "neural", "database", "operating system", "compiler", "web development"],
    "Mathematics": ["math", "calculus", "linear algebra", "statistics", "probability", "differential", "topology", "abstract algebra", "number theory", "geometry", "discrete"],
    "Physics": ["physics", "mechanics", "quantum", "thermodynamics", "electromagnetism", "relativity", "optics", "waves", "astrophysics"],
    "Chemistry": ["chemistry", "organic", "inorganic", "biochemistry", "chemical"],
    "Biology": ["biology", "genetics", "ecology", "evolution", "anatomy", "physiology", "neuroscience", "microbiology", "cell biology"],
    "Economics": ["economics", "microeconomics", "macroeconomics", "finance", "econometrics", "game theory"],
    "Philosophy": ["philosophy", "ethics", "logic", "epistemology", "metaphysics", "moral"],
    "History": ["history", "civilization", "ancient", "medieval", "revolution", "war"],
    "Psychology": ["psychology", "cognitive", "behavioral", "social psychology", "developmental"],
    "Engineering": ["engineering", "circuits", "signals", "control", "robotics", "aerospace", "mechanical", "electrical", "civil"],
    "Literature": ["literature", "poetry", "writing", "literary", "novel", "fiction"],
    "Political Science": ["political", "government", "democracy", "international relations", "policy"],
    "Astronomy": ["astronomy", "astrophysics", "cosmology", "planets", "stars", "universe"],
    "Music": ["music", "composition", "harmony", "theory of music"],
    "Art & Design": ["art", "architecture", "design", "visual", "aesthetic"],
}


def infer_department(title):
    """Infer department from playlist title using keyword matching."""
    title_lower = title.lower()
    for dept, keywords in DEPT_KEYWORDS.items():
        for kw in keywords:
            if kw in title_lower:
                return dept
    return "General"


def api_call(endpoint, params, api_key):
    """Make a YouTube Data API call."""
    params["key"] = api_key
    url = f"{API_BASE}/{endpoint}?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "MITReels-Discovery/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        print(f"  API error: {e}")
        return None


def fetch_all_playlists(channel_id, api_key):
    """Fetch all playlists from a channel (paginated)."""
    playlists = []
    page_token = None

    while True:
        params = {
            "part": "snippet,contentDetails",
            "channelId": channel_id,
            "maxResults": "50",
        }
        if page_token:
            params["pageToken"] = page_token

        data = api_call("playlists", params, api_key)
        if not data or "items" not in data:
            break

        for item in data["items"]:
            count = item.get("contentDetails", {}).get("itemCount", 0)
            title = item["snippet"]["title"]
            playlists.append({
                "id": item["id"],
                "title": title,
                "description": item["snippet"].get("description", ""),
                "itemCount": count,
            })

        page_token = data.get("nextPageToken")
        if not page_token:
            break
        time.sleep(0.1)  # Be polite

    return playlists


def fetch_playlist_videos(playlist_id, api_key, max_videos=3):
    """Fetch first N videos from a playlist."""
    params = {
        "part": "snippet",
        "playlistId": playlist_id,
        "maxResults": str(max_videos),
    }

    data = api_call("playlistItems", params, api_key)
    if not data or "items" not in data:
        return []

    videos = []
    for item in data["items"]:
        snippet = item["snippet"]
        resource = snippet.get("resourceId", {})
        if resource.get("kind") != "youtube#video":
            continue
        video_id = resource.get("videoId", "")
        if not video_id or len(video_id) != 11:
            continue

        videos.append({
            "videoId": video_id,
            "title": snippet.get("title", ""),
            "description": snippet.get("description", ""),
            "position": snippet.get("position", 0),
        })

    return videos


def is_course_like(playlist):
    """Filter playlists that look like course content."""
    title = playlist["title"].lower()
    count = playlist["itemCount"]

    # Must have at least 3 videos
    if count < 3:
        return False

    # Skip obvious non-course playlists
    skip_keywords = [
        "trailer", "highlight", "short", "teaser", "promo",
        "behind the scene", "blooper", "best of", "compilation",
        "music video", "official video", "vlog", "q&a", "unboxing",
        "livestream", "live stream", "podcast episode",
    ]
    for kw in skip_keywords:
        if kw in title:
            return False

    return True


def extract_course_number(title, source_id):
    """Try to extract a course number from the playlist title."""
    import re

    # Common patterns: "CS229:", "15-445:", "ECON159:", "CS 61A", "6.006"
    patterns = [
        r'([A-Z]{2,4}\s?\d{2,4}[A-Z]?)',  # CS229, ECON159, CS 61A
        r'(\d{1,2}[-\.]\d{2,4})',           # 15-445, 6.006
        r'([A-Z]{2,4}\d{2,4})',             # CS229 without space
    ]

    for pattern in patterns:
        match = re.search(pattern, title)
        if match:
            return match.group(1).strip()

    # Fallback: use first few words as course number
    words = title.split()
    if len(words) >= 2:
        return " ".join(words[:min(3, len(words))])[:20]
    return title[:20]


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 discover_courses.py YOUR_YOUTUBE_API_KEY")
        sys.exit(1)

    api_key = sys.argv[1]

    all_lectures = []
    all_courses = []
    seen_video_ids = set()
    seen_course_keys = set()
    total_quota = 0

    for source_id, channel_name, channel_id in CHANNELS:
        print(f"\n{'='*60}")
        print(f"Discovering: {channel_name} ({source_id})")
        print(f"Channel ID: {channel_id}")
        print(f"{'='*60}")

        # Fetch all playlists
        playlists = fetch_all_playlists(channel_id, api_key)
        total_quota += (len(playlists) // 50) + 1
        print(f"  Found {len(playlists)} total playlists")

        # Filter to course-like playlists
        course_playlists = [p for p in playlists if is_course_like(p)]
        print(f"  {len(course_playlists)} course-like playlists (3+ videos, not promos)")

        # Fetch first 3 videos from each
        for playlist in course_playlists:
            videos = fetch_playlist_videos(playlist["id"], api_key, max_videos=3)
            total_quota += 1

            if not videos:
                continue

            # Deduplicate
            new_videos = [v for v in videos if v["videoId"] not in seen_video_ids]
            if not new_videos:
                continue

            course_number = extract_course_number(playlist["title"], source_id)
            department = infer_department(playlist["title"])
            course_key = f"{source_id}_{course_number}"

            # Add course
            if course_key not in seen_course_keys:
                seen_course_keys.add(course_key)
                all_courses.append({
                    "courseNumber": course_number,
                    "title": playlist["title"],
                    "department": department,
                    "semester": "",
                    "year": 0,
                    "sourceId": source_id,
                })

            # Add lectures (first 3)
            for video in new_videos:
                if video["videoId"] in seen_video_ids:
                    continue
                seen_video_ids.add(video["videoId"])

                all_lectures.append({
                    "title": video["title"],
                    "youtubeId": video["videoId"],
                    "courseNumber": course_number,
                    "courseName": playlist["title"],
                    "department": department,
                    "semester": "",
                    "year": 0,
                    "ocwUrl": "",
                    "topicName": department,
                    "sourceId": source_id,
                })

            time.sleep(0.05)  # Rate limiting

        source_courses = sum(1 for c in all_courses if c["sourceId"] == source_id)
        source_lectures = sum(1 for l in all_lectures if l["sourceId"] == source_id)
        print(f"  → {source_courses} courses, {source_lectures} lectures")

    # Write output
    output = {
        "lectures": all_lectures,
        "courses": all_courses,
    }

    output_path = "MITReels/Resources/multi_source_seed.json"
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"\n{'='*60}")
    print(f"DONE!")
    print(f"{'='*60}")
    print(f"Total courses: {len(all_courses)}")
    print(f"Total lectures: {len(all_lectures)}")
    print(f"Quota used: ~{total_quota} units")
    print(f"Output: {output_path}")

    # Summary by source
    print(f"\nBy source:")
    from collections import Counter
    course_counts = Counter(c["sourceId"] for c in all_courses)
    lecture_counts = Counter(l["sourceId"] for l in all_lectures)
    for src in sorted(set(course_counts.keys()) | set(lecture_counts.keys())):
        print(f"  {src}: {course_counts.get(src, 0)} courses, {lecture_counts.get(src, 0)} lectures")


if __name__ == "__main__":
    main()
