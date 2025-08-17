# Issue #26: Advanced PlexAPI Integration and Smart Scanning

**Priority:** Medium  
**Type:** Enhancement  
**Status:** Ready for Implementation  
**Assignee:** GitHub Copilot Coding Agent  

## 🎯 Objective

Enhance the Plex notification system in `media_update.py` to use advanced PlexAPI features for more intelligent, efficient, and reliable Plex library management. This builds upon the robust error handling and batch notification system implemented in Issue #25.

## 🏗️ Current Implementation (Issue #25 - COMPLETED)

✅ **Basic PlexAPI Integration:**
- Uses `PlexServer` and `section.update()` for library scanning
- String-based path matching (`'tv' in file_path_lower`)
- Section-wide library scans
- REST API fallback for compatibility
- Robust error handling with retries
- Batch notification system

## 🚀 Proposed Enhancements

### **1. Intelligent Path Resolution**
**Current Problem:** Basic string matching may incorrectly categorize files
```python
# Current: Crude string matching
if 'tv' in file_path_lower or '/tv/' in file_path_lower:
    sections_to_update.append(section)
```

**Enhancement:** Use PlexAPI's actual library locations
```python
# Enhanced: Precise path resolution
from pathlib import Path
for section in plex.library.sections():
    for location in section.locations:
        if Path(file_path).is_relative_to(Path(location)):
            sections_to_update.append(section)
            logging.info(f"File matches library location: {location}")
```

### **2. Granular Directory Scanning**
**Current Problem:** Scans entire library sections (inefficient for large libraries)
```python
# Current: Full section scan
section.update()  # Scans thousands of files
```

**Enhancement:** Target specific directories or files
```python
# Enhanced: Targeted scanning
file_dir = os.path.dirname(file_path)
section.update(path=file_dir)  # Only scans relevant directory
logging.info(f"Targeted scan of directory: {file_dir}")
```

### **3. Media Validation and Feedback**
**Current Problem:** No verification that Plex successfully processed files
```python
# Current: Fire and forget
section.update()
logging.info("Scan triggered")
```

**Enhancement:** Validate Plex found and processed the media
```python
# Enhanced: Validation and feedback
section.update(path=file_dir)

# Wait briefly and verify file was found
time.sleep(2)
try:
    # Search for the file in Plex
    search_results = section.search(filepath=file_path)
    if search_results:
        media_item = search_results[0]
        logging.info(f"✅ Plex successfully processed: {media_item.title}")
        logging.info(f"   Duration: {media_item.duration}ms, Bitrate: {media_item.bitrate}")
    else:
        logging.warning(f"⚠️ File not found in Plex after scan: {file_path}")
except Exception as e:
    logging.warning(f"⚠️ Could not verify file in Plex: {e}")
```

### **4. Duplicate Detection**
**Current Problem:** No check if files already exist in Plex
```python
# Current: Always triggers scan
section.update()
```

**Enhancement:** Skip scanning if file already exists and is up-to-date
```python
# Enhanced: Smart duplicate detection
try:
    existing_media = section.search(filepath=file_path)
    if existing_media:
        media_item = existing_media[0]
        file_mtime = os.path.getmtime(file_path)
        plex_updated = media_item.updatedAt.timestamp()
        
        if file_mtime <= plex_updated:
            logging.info(f"⏭️ File already up-to-date in Plex: {media_item.title}")
            return True
        else:
            logging.info(f"🔄 File modified since last Plex scan, updating...")
    else:
        logging.info(f"🆕 New file for Plex library")
except Exception as e:
    logging.debug(f"Could not check existing media: {e}")

# Proceed with scan
section.update(path=file_dir)
```

### **5. Enhanced Library Analytics**
**Current Problem:** Limited feedback about library state
```python
# Current: Basic logging
logging.info("Successfully triggered scan")
```

**Enhancement:** Rich library information and analytics
```python
# Enhanced: Detailed library analytics  
before_count = section.totalSize
section.update(path=file_dir)

# Brief wait for scan completion
time.sleep(3)
after_count = section.totalSize

if after_count > before_count:
    logging.info(f"📈 Library updated: {section.title}")
    logging.info(f"   Added {after_count - before_count} new items")
    logging.info(f"   Total items: {after_count}")
    logging.info(f"   Library size: {section.totalDuration // 3600000}h of content")
else:
    logging.info(f"📊 Library scan completed, no new items detected")
```

### **6. Smart Retry Logic**
**Current Problem:** Generic retry for all errors
```python
# Current: Blanket retry
if attempt < retry_count:
    time.sleep(5)
    continue
```

**Enhancement:** Intelligent retry based on error type
```python
# Enhanced: Smart retry logic
except PlexServerError as e:
    if "scanning" in str(e).lower():
        logging.info(f"📡 Library scan in progress, waiting...")
        time.sleep(10)  # Longer wait for active scans
    elif "timeout" in str(e).lower():
        logging.info(f"⏰ Scan timeout, retrying with longer timeout...")
        plex._timeout = 30  # Increase timeout
    else:
        logging.warning(f"🔄 Server error, standard retry: {e}")
        time.sleep(5)
```

## 🔧 Implementation Requirements

### **File Modifications Required:**
1. **`scripts/media_update.py`** - Primary enhancement target
2. **`scripts/requirements.txt`** - Ensure PlexAPI version supports new features
3. **Documentation updates** - Update README with new capabilities

### **PlexAPI Version Requirements:**
```python
# Verify minimum PlexAPI version for advanced features
PlexAPI>=4.15.8  # Current version
# May need newer version for specific features
```

### **Backward Compatibility:**
- ✅ Maintain existing REST API fallback
- ✅ Graceful degradation if advanced features unavailable
- ✅ All existing configuration options preserved
- ✅ Current error handling maintained

### **Configuration Options:**
Add new optional settings to `.env`:
```bash
# Advanced PlexAPI features (optional)
PLEX_SMART_SCANNING=true           # Enable intelligent scanning
PLEX_VALIDATE_MEDIA=true           # Verify files processed successfully
PLEX_DUPLICATE_DETECTION=true      # Skip already-processed files
PLEX_DETAILED_LOGGING=true         # Enhanced logging and analytics
```

## 🧪 Testing Requirements

### **Test Cases:**
1. **Path Resolution Test:**
   - Files in nested TV show directories
   - Movies in subdirectories
   - Music in artist/album structures
   - Edge case: Files outside library paths

2. **Scanning Efficiency Test:**
   - Large library performance comparison (before/after)
   - Multiple files in same directory (batch efficiency)
   - Single file updates

3. **Validation Test:**
   - Successful media processing verification
   - Failed/corrupted file detection
   - Network timeout handling

4. **Duplicate Detection Test:**
   - Same file processed twice
   - Modified file timestamps
   - Different file, same name

### **Performance Benchmarks:**
- **Current:** Section scan time for 1000+ item libraries
- **Target:** <50% scan time reduction through targeted scanning
- **Memory:** Monitor PlexAPI object memory usage

## 📋 Implementation Plan

### **Phase 1: Core Enhancements** (High Priority)
1. Implement intelligent path resolution
2. Add granular directory scanning
3. Basic media validation
4. Update error handling for new features

### **Phase 2: Advanced Features** (Medium Priority)  
1. Duplicate detection logic
2. Enhanced library analytics
3. Smart retry mechanisms
4. Configuration options

### **Phase 3: Optimization** (Low Priority)
1. Performance tuning
2. Memory usage optimization
3. Concurrent scanning for multiple files
4. Advanced caching

## 🛡️ Error Handling Requirements

### **Maintain Existing Robustness:**
- ✅ All current retry logic preserved
- ✅ Graceful degradation when PlexAPI unavailable
- ✅ Network timeout handling
- ✅ Authentication error recovery

### **New Error Scenarios:**
```python
# Handle advanced PlexAPI errors
try:
    section.update(path=file_dir)
except PlexPartialUpdateError:
    logging.warning("Partial scan completed, some files may need retry")
except PlexLibraryBusyError:
    logging.info("Library busy, scheduling retry")
except PlexPermissionError:  
    logging.error("Insufficient permissions for targeted scanning")
```

## 📖 Documentation Requirements

### **Update README.md:**
- New PlexAPI capabilities section
- Configuration options explanation
- Performance benefits description

### **Code Documentation:**
- Comprehensive docstrings for new functions
- Inline comments explaining PlexAPI usage
- Configuration examples

## ✅ Acceptance Criteria

### **Functional Requirements:**
- [ ] Files correctly matched to library sections using actual paths
- [ ] Targeted directory scanning instead of full library scans
- [ ] Media validation confirms successful Plex processing
- [ ] Duplicate detection prevents unnecessary rescans
- [ ] Enhanced logging provides actionable feedback
- [ ] Smart retry logic handles different error types appropriately

### **Performance Requirements:**
- [ ] >30% reduction in scan time for large libraries
- [ ] <2 second response time for single file notifications
- [ ] Memory usage remains stable under continuous operation

### **Reliability Requirements:**
- [ ] All existing error handling preserved
- [ ] Graceful fallback to current method if advanced features fail
- [ ] No regression in notification success rate
- [ ] Compatible with existing configuration

### **Usability Requirements:**  
- [ ] New features configurable via `.env` file
- [ ] Enhanced logging provides clear, actionable information
- [ ] Documentation updated with new capabilities
- [ ] Backward compatible with existing installations

## 🚀 Expected Benefits

### **Performance:**
- **30-50% faster** library scanning for large collections
- **Reduced Plex server load** through targeted scanning
- **Lower network traffic** with smart duplicate detection

### **Reliability:**
- **Better error diagnosis** with detailed PlexAPI feedback
- **Smarter retry logic** based on actual error conditions  
- **Media validation** ensures successful processing

### **User Experience:**
- **Detailed logging** shows exactly what Plex processed
- **Configurable features** allow customization per environment
- **Better feedback** on scan results and library changes

## 📝 Implementation Notes for Coding Agent

### **Code Style:**
- Follow existing code style in `media_update.py`
- Maintain consistent error handling patterns
- Use descriptive logging messages with emojis for readability
- Add comprehensive docstrings

### **Testing Integration:**
- Ensure compatibility with existing test suite
- Add new test cases for PlexAPI features
- Test with existing `.env` configurations

### **Safety First:**
- All new features should gracefully degrade if unavailable
- Maintain existing REST API fallback behavior
- Preserve all current configuration options

### **Key Files to Reference:**
- `scripts/media_update.py` - Main implementation target
- `.env` - Configuration integration
- `scripts/requirements.txt` - Dependencies
- Issue #25 implementation - Base functionality to build upon

**This issue is ready for the GitHub Copilot coding agent to implement during weekend development session.**
