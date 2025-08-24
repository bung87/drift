## Test file for file tab data structures and basic functionality

import std/[unittest, times, options, tables]
import raylib as rl
import ../src/components/file_tabs
import ../src/services/ui_service

# Mock UIService for testing
proc createMockUIService(): UIService =
  # Create a minimal UIService for testing
  result = UIService()
  result.components = initTable[string, UIComponent]()

suite "File Tab Data Structures":
  
  test "FileTab creation and basic properties":
    let tab = newFileTab("tab1", "/path/to/file.nim", "file.nim", "file.nim")
    
    check tab.id == "tab1"
    check tab.filePath == "/path/to/file.nim"
    check tab.fileName == "file.nim"
    check tab.displayName == "file.nim"
    check tab.fullPath == "/path/to/file.nim"
    check tab.state == ftsNormal
    check tab.isModified == false
    check tab.isClosable == true
    
  test "FileTab with automatic filename extraction":
    let tab = newFileTab("tab2", "/path/to/another/test.txt")
    
    check tab.fileName == "test.txt"
    check tab.displayName == "test.txt"
    
  test "FileTab state management":
    let tab = newFileTab("tab3", "/test.nim")
    
    # Test state updates
    tab.updateState(ftsActive)
    check tab.state == ftsActive
    
    tab.updateState(ftsHover)
    check tab.state == ftsHover
    
  test "FileTab modification state":
    let tab = newFileTab("tab4", "/test.nim")
    
    # Test modification state
    tab.setModified(true)
    check tab.isModified == true
    check tab.state == ftsModified
    
    tab.setModified(false)
    check tab.isModified == false
    check tab.state == ftsNormal
    
  test "FileTab bounds calculation":
    let tab = newFileTab("tab5", "/test.nim")
    
    tab.calculateTabBounds(10.0, 20.0, 150.0, 32.0)
    
    check tab.bounds.x == 10.0
    check tab.bounds.y == 20.0
    check tab.bounds.width == 150.0
    check tab.bounds.height == 32.0
    
    # Check close button bounds (16x16, 4px from right)
    check tab.closeButtonBounds.width == 16.0
    check tab.closeButtonBounds.height == 16.0
    check tab.closeButtonBounds.x == 10.0 + 150.0 - 16.0 - 4.0  # x + width - buttonSize - margin
    
  test "FileTab point collision detection":
    let tab = newFileTab("tab6", "/test.nim")
    tab.calculateTabBounds(0.0, 0.0, 100.0, 32.0)
    
    # Test point in tab
    check tab.isPointInTab(50.0, 16.0) == true
    check tab.isPointInTab(150.0, 16.0) == false
    
    # Test point in close button
    check tab.isPointInCloseButton(85.0, 16.0) == true  # Should be in close button area
    check tab.isPointInCloseButton(10.0, 16.0) == false  # Should not be in close button area

suite "FileTabBar Component":
  
  test "FileTabBar creation":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar1", uiService)
    
    check tabBar.id == "tabbar1"
    check tabBar.name == "FileTabBar"
    check tabBar.tabs.len == 0
    check tabBar.activeTabIndex == -1
    check tabBar.maxTabWidth == 240.0
    check tabBar.minTabWidth == 120.0
    check tabBar.tabHeight == 32.0
    
  test "FileTabBar tab management":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar2", uiService)
    
    # Add first tab
    let tab1 = newFileTab("tab1", "/file1.nim")
    let index1 = tabBar.addTab(tab1)
    
    check index1 == 0
    check tabBar.tabs.len == 1
    check tabBar.activeTabIndex == 0
    check tab1.state == ftsActive
    
    # Add second tab
    let tab2 = newFileTab("tab2", "/file2.nim")
    let index2 = tabBar.addTab(tab2)
    
    check index2 == 1
    check tabBar.tabs.len == 2
    check tabBar.activeTabIndex == 0  # First tab should still be active
    check tab2.state == ftsNormal
    
  test "FileTabBar active tab management":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar3", uiService)
    
    let tab1 = newFileTab("tab1", "/file1.nim")
    let tab2 = newFileTab("tab2", "/file2.nim")
    
    discard tabBar.addTab(tab1)
    discard tabBar.addTab(tab2)
    
    # Switch to second tab
    check tabBar.setActiveTab(1) == true
    check tabBar.activeTabIndex == 1
    check tab1.state == ftsNormal
    check tab2.state == ftsActive
    
    # Test invalid index
    check tabBar.setActiveTab(5) == false
    check tabBar.activeTabIndex == 1  # Should remain unchanged
    
  test "FileTabBar tab removal":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar4", uiService)
    
    let tab1 = newFileTab("tab1", "/file1.nim")
    let tab2 = newFileTab("tab2", "/file2.nim")
    let tab3 = newFileTab("tab3", "/file3.nim")
    
    discard tabBar.addTab(tab1)
    discard tabBar.addTab(tab2)
    discard tabBar.addTab(tab3)
    
    # Remove middle tab
    check tabBar.removeTab(1) == true
    check tabBar.tabs.len == 2
    check tabBar.tabs[0] == tab1
    check tabBar.tabs[1] == tab3
    
    # Test invalid removal
    check tabBar.removeTab(5) == false
    check tabBar.tabs.len == 2
    
  test "FileTabBar find tab by path":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar5", uiService)
    
    let tab1 = newFileTab("tab1", "/path/file1.nim")
    let tab2 = newFileTab("tab2", "/path/file2.nim")
    
    discard tabBar.addTab(tab1)
    discard tabBar.addTab(tab2)
    
    # Find existing tab
    let found = tabBar.findTabByPath("/path/file2.nim")
    check found.isSome()
    check found.get() == 1
    
    # Find non-existing tab
    let notFound = tabBar.findTabByPath("/path/file3.nim")
    check notFound.isNone()
    
  test "FileTabBar get active tab":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar6", uiService)
    
    # No active tab initially
    let noActive = tabBar.getActiveTab()
    check noActive.isNone()
    
    # Add tab and check active
    let tab1 = newFileTab("tab1", "/file1.nim")
    discard tabBar.addTab(tab1)
    
    let active = tabBar.getActiveTab()
    check active.isSome()
    check active.get() == tab1

suite "Tab Display Name Resolution":
  
  test "resolveDisplayPaths with no conflicts":
    let paths = @[
      "/project/src/main.nim",
      "/project/src/utils.nim",
      "/project/tests/test_main.nim"
    ]
    
    let result = resolveDisplayPaths(paths)
    
    check result["/project/src/main.nim"].displayName == "main.nim"
    check result["/project/src/utils.nim"].displayName == "utils.nim"
    check result["/project/tests/test_main.nim"].displayName == "test_main.nim"
    check result["/project/src/main.nim"].showPath == false
    check result["/project/src/utils.nim"].showPath == false
    check result["/project/tests/test_main.nim"].showPath == false
    
  test "resolveDisplayPaths with filename conflicts":
    let paths = @[
      "/project/src/main.nim",
      "/project/tests/main.nim",
      "/project/examples/main.nim"
    ]
    
    let result = resolveDisplayPaths(paths)
    
    # Should show enough path to distinguish the files
    check result["/project/src/main.nim"].displayName == "src/main.nim"
    check result["/project/tests/main.nim"].displayName == "tests/main.nim"
    check result["/project/examples/main.nim"].displayName == "examples/main.nim"
    check result["/project/src/main.nim"].showPath == true
    check result["/project/tests/main.nim"].showPath == true
    check result["/project/examples/main.nim"].showPath == true
    
  test "resolveDisplayPaths with nested conflicts":
    let paths = @[
      "/project/src/components/main.nim",
      "/project/src/services/main.nim",
      "/project/tests/unit/main.nim",
      "/project/tests/integration/main.nim"
    ]
    
    let result = resolveDisplayPaths(paths)
    
    # Should show enough path to distinguish all files
    check result["/project/src/components/main.nim"].displayName == "components/main.nim"
    check result["/project/src/services/main.nim"].displayName == "services/main.nim"
    check result["/project/tests/unit/main.nim"].displayName == "unit/main.nim"
    check result["/project/tests/integration/main.nim"].displayName == "integration/main.nim"
    
  test "resolveDisplayPaths with single file":
    let paths = @["/project/src/main.nim"]
    
    let result = resolveDisplayPaths(paths)
    
    check result["/project/src/main.nim"].displayName == "main.nim"
    check result["/project/src/main.nim"].showPath == false
    check result["/project/src/main.nim"].tooltip == "/project/src/main.nim"
    
  test "resolveDisplayPaths with empty input":
    let paths: seq[string] = @[]
    
    let result = resolveDisplayPaths(paths)
    
    check result.len == 0
    
  test "resolveDisplayPaths with same directory files":
    let paths = @[
      "/project/src/main.nim",
      "/project/src/utils.nim",
      "/project/src/config.nim"
    ]
    
    let result = resolveDisplayPaths(paths)
    
    # No conflicts, should show just filenames
    check result["/project/src/main.nim"].displayName == "main.nim"
    check result["/project/src/utils.nim"].displayName == "utils.nim"
    check result["/project/src/config.nim"].displayName == "config.nim"
    check result["/project/src/main.nim"].showPath == false
    
  test "resolveDisplayPaths with complex nested structure":
    let paths = @[
      "/project/src/components/ui/button.nim",
      "/project/src/components/layout/button.nim",
      "/project/tests/components/ui/button.nim",
      "/project/examples/button.nim"
    ]
    
    let result = resolveDisplayPaths(paths)
    
    # Should distinguish all button.nim files
    check result["/project/src/components/ui/button.nim"].displayName == "ui/button.nim"
    check result["/project/src/components/layout/button.nim"].displayName == "layout/button.nim"
    check result["/project/tests/components/ui/button.nim"].displayName == "tests/components/ui/button.nim"
    check result["/project/examples/button.nim"].displayName == "examples/button.nim"
    
  test "resolveDisplayPaths with root level files":
    let paths = @[
      "/main.nim",
      "/config.nim"
    ]
    
    let result = resolveDisplayPaths(paths)
    
    check result["/main.nim"].displayName == "main.nim"
    check result["/config.nim"].displayName == "config.nim"
    check result["/main.nim"].showPath == false
    
  test "resolveDisplayPaths tooltips":
    let paths = @[
      "/very/long/path/to/project/src/main.nim",
      "/another/long/path/to/project/tests/main.nim"
    ]
    
    let result = resolveDisplayPaths(paths)
    
    check result["/very/long/path/to/project/src/main.nim"].tooltip == "/very/long/path/to/project/src/main.nim"
    check result["/another/long/path/to/project/tests/main.nim"].tooltip == "/another/long/path/to/project/tests/main.nim"

suite "Tab Display Name Integration":
  
  test "updateTabDisplayNames with no conflicts":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar_display1", uiService)
    
    let tab1 = newFileTab("tab1", "/project/src/main.nim")
    let tab2 = newFileTab("tab2", "/project/src/utils.nim")
    
    discard tabBar.addTab(tab1)
    discard tabBar.addTab(tab2)
    
    check tab1.displayName == "main.nim"
    check tab2.displayName == "utils.nim"
    check tab1.getTabTooltip() == "/project/src/main.nim"
    check tab2.getTabTooltip() == "/project/src/utils.nim"
    
  test "updateTabDisplayNames with conflicts":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar_display2", uiService)
    
    let tab1 = newFileTab("tab1", "/project/src/main.nim")
    let tab2 = newFileTab("tab2", "/project/tests/main.nim")
    
    discard tabBar.addTab(tab1)
    discard tabBar.addTab(tab2)
    
    check tab1.displayName == "src/main.nim"
    check tab2.displayName == "tests/main.nim"
    check tab1.shouldShowPath() == true
    check tab2.shouldShowPath() == true
    
  test "updateTabDisplayNames after tab removal":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar_display3", uiService)
    
    let tab1 = newFileTab("tab1", "/project/src/main.nim")
    let tab2 = newFileTab("tab2", "/project/tests/main.nim")
    let tab3 = newFileTab("tab3", "/project/src/utils.nim")
    
    discard tabBar.addTab(tab1)
    discard tabBar.addTab(tab2)
    discard tabBar.addTab(tab3)
    
    # Initially should have conflicts for main.nim files
    check tab1.displayName == "src/main.nim"
    check tab2.displayName == "tests/main.nim"
    check tab3.displayName == "utils.nim"
    
    # Remove one of the conflicting tabs
    discard tabBar.removeTab(1)  # Remove tests/main.nim
    
    # Now main.nim should show just filename since no conflict
    check tab1.displayName == "main.nim"
    check tab3.displayName == "utils.nim"
    check tab1.shouldShowPath() == false
    
  test "addTabByPath with display name resolution":
    let uiService = createMockUIService()
    let tabBar = newFileTabBar("tabbar_display4", uiService)
    
    # Add tabs using path-based method
    discard tabBar.addTabByPath("/project/src/main.nim")
    discard tabBar.addTabByPath("/project/tests/main.nim")
    discard tabBar.addTabByPath("/project/src/utils.nim")
    
    check tabBar.tabs[0].displayName == "src/main.nim"
    check tabBar.tabs[1].displayName == "tests/main.nim"
    check tabBar.tabs[2].displayName == "utils.nim"