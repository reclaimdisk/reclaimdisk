/// The rules that read a finished scan and propose build folders, dependency folders and environments.
public enum ScanRules {
    public static let rustBuildFolder: any Rule = RustBuildFolderRule()
    public static let nodeDependencies: any Rule = NodeDependenciesRule()
    public static let javaScriptBuildCaches: any Rule = JavaScriptBuildCachesRule()
    public static let pythonEnvironment: any Rule = PythonEnvironmentRule()

    public static let all: [any Rule] = [rustBuildFolder, nodeDependencies, javaScriptBuildCaches, pythonEnvironment]
}
