import SwiftProtobufPluginLibrary

/// Responsible for generating services and RPCs that are compatible with the Connect library.
final class ConnectGenerator {
    private let descriptor: FileDescriptor
    private let namer: SwiftProtobufNamer
    private let options: GeneratorOptions
    private var printer = CodePrinter(indent: "    ".unicodeScalars)
    private let visibility: String

    var output: String {
        return self.printer.content
    }

    init(_ descriptor: FileDescriptor, options: GeneratorOptions) {
        self.descriptor = descriptor
        self.options = options
        self.namer = SwiftProtobufNamer(
            currentFile: descriptor,
            protoFileToModuleMappings: options.protoToModuleMappings
        )
        switch options.visibility {
        case .internal:
            self.visibility = "internal"
        case .public:
            self.visibility = "public"
        }

        self.printContent()
    }

    // MARK: - Output helpers

    private func indent() {
        self.printer.indent()
    }

    private func outdent() {
        self.printer.outdent()
    }

    private func indent(printLines: () -> Void) {
        self.indent()
        printLines()
        self.outdent()
    }

    private func printLine(_ line: String = "") {
        if !line.isEmpty {
            self.printer.print(line)
        }
        self.printer.print("\n")
    }

    private func printCommentsIfNeeded(for entity: ProvidesSourceCodeLocation) {
        let comments = entity.protoSourceComments().trimmingCharacters(in: .whitespacesAndNewlines)
        if !comments.isEmpty {
            self.printLine(comments)
        }
    }

    // MARK: - Output content

    private func printContent() {
        self.printLine("// Code generated by protoc-gen-connect-swift. DO NOT EDIT.")
        self.printLine("//")
        self.printLine("// Source: \(self.descriptor.name)")
        self.printLine("//")
        self.printLine()

        for module in self.modulesToImport() {
            self.printLine("import \(module)")
        }

        for service in self.descriptor.services {
            self.printLine()
            self.printService(service)
        }
    }

    private func modulesToImport() -> [String] {
        let defaults = ["Connect", "Foundation", self.options.swiftProtobufModuleName]
        let extras = self.options.extraModuleImports
        let mappings = self.options.protoToModuleMappings
            .neededModules(forFile: self.descriptor) ?? []
        return (defaults + mappings + extras).sorted()
    }

    private func printService(_ service: ServiceDescriptor) {
        self.printCommentsIfNeeded(for: service)

        let protocolName = service.protocolName(using: self.namer)
        self.printLine("\(self.visibility) protocol \(protocolName) {")
        self.indent {
            for method in service.methods {
                if self.options.generateCallbackMethods {
                    self.printCallbackMethodInterface(for: method)
                }
                if self.options.generateAsyncMethods {
                    self.printAsyncAwaitMethodInterface(for: method)
                }
            }
        }
        self.printLine("}")

        self.printLine()

        let className = service.implementationName(using: self.namer)
        self.printLine("/// Concrete implementation of `\(protocolName)`.")
        self.printLine("\(self.visibility) final class \(className): \(protocolName) {")
        self.indent {
            self.printLine("private let client: Connect.ProtocolClientInterface")
            self.printLine()
            self.printLine("\(self.visibility) init(client: Connect.ProtocolClientInterface) {")
            self.indent {
                self.printLine("self.client = client")
            }
            self.printLine("}")

            for method in service.methods {
                if self.options.generateCallbackMethods {
                    self.printCallbackMethodImplementation(for: method)
                }
                if self.options.generateAsyncMethods {
                    self.printAsyncAwaitMethodImplementation(for: method)
                }
            }
        }
        self.printLine("}")
    }

    private func printCallbackMethodInterface(for method: MethodDescriptor) {
        self.printLine()
        self.printCommentsIfNeeded(for: method)
        if !method.serverStreaming && !method.clientStreaming {
            self.printLine("@discardableResult")
        }

        self.printLine(
            method.callbackSignature(using: namer, includeDefaults: false, options: self.options)
        )
    }

    private func printAsyncAwaitMethodInterface(for method: MethodDescriptor) {
        self.printLine()
        self.printCommentsIfNeeded(for: method)
        self.printLine(
            method.asyncAwaitSignature(using: namer, includeDefaults: false, options: self.options)
        )
    }

    private func printCallbackMethodImplementation(for method: MethodDescriptor) {
        self.printLine()
        if !method.serverStreaming && !method.clientStreaming {
            self.printLine("@discardableResult")
        }

        self.printLine(
            "\(self.visibility) "
            + method.callbackSignature(using: namer, includeDefaults: true, options: self.options)
            + " {"
        )
        self.indent {
            self.printLine("return \(method.callbackReturnValue())")
        }
        self.printLine("}")
    }

    private func printAsyncAwaitMethodImplementation(for method: MethodDescriptor) {
        self.printLine()
        self.printLine(
            "\(self.visibility) "
            + method.asyncAwaitSignature(using: namer, includeDefaults: true, options: self.options)
            + " {"
        )
        self.indent {
            self.printLine("return \(method.asyncAwaitReturnValue())")
        }
        self.printLine("}")
    }
}

private extension ServiceDescriptor {
    func protocolName(using namer: SwiftProtobufNamer) -> String {
        return self.implementationName(using: namer) + "Interface"
    }

    func implementationName(using namer: SwiftProtobufNamer) -> String {
        let upperCamelName = NamingUtils.toUpperCamelCase(self.name) + "Client"
        if self.file.package.isEmpty {
            return upperCamelName
        } else {
            return namer.typePrefix(forFile: self.file) + upperCamelName
        }
    }
}

private extension MethodDescriptor {
    var methodPath: String {
        if self.file.package.isEmpty {
            return "\(self.service.name)/\(self.name)"
        } else {
            return "\(self.file.package).\(self.service.name)/\(self.name)"
        }
    }

    func name(using options: GeneratorOptions) -> String {
        return options.keepMethodCasing
            ? self.name
            : NamingUtils.toLowerCamelCase(self.name)
    }

    func callbackSignature(
        using namer: SwiftProtobufNamer, includeDefaults: Bool, options: GeneratorOptions
    ) -> String {
        let methodName = self.name(using: options)
        let inputName = namer.fullName(message: self.inputType)
        let outputName = namer.fullName(message: self.outputType)

        // Note that the method name is escaped to avoid using Swift keywords.
        if self.clientStreaming && self.serverStreaming {
            return """
            func `\(methodName)`\
            (headers: Connect.Headers\(includeDefaults ? " = [:]" : ""), \
            onResult: @escaping (Connect.StreamResult<\(outputName)>) -> Void) \
            -> any Connect.BidirectionalStreamInterface<\(inputName)>
            """

        } else if self.serverStreaming {
            return """
            func `\(methodName)`\
            (headers: Connect.Headers\(includeDefaults ? " = [:]" : ""), \
            onResult: @escaping (Connect.StreamResult<\(outputName)>) -> Void) \
            -> any Connect.ServerOnlyStreamInterface<\(inputName)>
            """

        } else if self.clientStreaming {
            return """
            func `\(methodName)`\
            (headers: Connect.Headers\(includeDefaults ? " = [:]" : ""), \
            onResult: @escaping (Connect.StreamResult<\(outputName)>) -> Void) \
            -> any Connect.ClientOnlyStreamInterface<\(inputName)>
            """

        } else {
            return """
            func `\(methodName)`\
            (request: \(inputName), headers: Connect.Headers\(includeDefaults ? " = [:]" : ""), \
            completion: @escaping (ResponseMessage<\(outputName)>) -> Void) \
            -> Connect.Cancelable
            """
        }
    }

    func asyncAwaitSignature(
        using namer: SwiftProtobufNamer, includeDefaults: Bool, options: GeneratorOptions
    ) -> String {
        let methodName = self.name(using: options)
        let inputName = namer.fullName(message: self.inputType)
        let outputName = namer.fullName(message: self.outputType)

        // Note that the method name is escaped to avoid using Swift keywords.
        if self.clientStreaming && self.serverStreaming {
            return """
            func `\(methodName)`\
            (headers: Connect.Headers\(includeDefaults ? " = [:]" : "")) \
            -> any Connect.BidirectionalAsyncStreamInterface<\(inputName), \(outputName)>
            """

        } else if self.serverStreaming {
            return """
            func `\(methodName)`\
            (headers: Connect.Headers\(includeDefaults ? " = [:]" : "")) \
            -> any Connect.ServerOnlyAsyncStreamInterface<\(inputName), \(outputName)>
            """

        } else if self.clientStreaming {
            return """
            func `\(methodName)`\
            (headers: Connect.Headers\(includeDefaults ? " = [:]" : "")) \
            -> any Connect.ClientOnlyAsyncStreamInterface<\(inputName), \(outputName)>
            """

        } else {
            return """
            func `\(methodName)`\
            (request: \(inputName), headers: Connect.Headers\(includeDefaults ? " = [:]" : "")) \
            async -> ResponseMessage<\(outputName)>
            """
        }
    }

    func callbackReturnValue() -> String {
        if self.clientStreaming && self.serverStreaming {
            return """
            self.client.bidirectionalStream(\
            path: "\(self.methodPath)", headers: headers, onResult: onResult)
            """
        } else if self.serverStreaming {
            return """
            self.client.serverOnlyStream(\
            path: "\(self.methodPath)", headers: headers, onResult: onResult)
            """
        } else if self.clientStreaming {
            return """
            self.client.clientOnlyStream(\
            path: "\(self.methodPath)", headers: headers, onResult: onResult)
            """
        } else {
            return """
            self.client.unary(\
            path: "\(self.methodPath)", request: request, headers: headers, completion: completion)
            """
        }
    }

    func asyncAwaitReturnValue() -> String {
        if self.clientStreaming && self.serverStreaming {
            return """
            self.client.bidirectionalStream(path: "\(self.methodPath)", headers: headers)
            """
        } else if self.serverStreaming {
            return """
            self.client.serverOnlyStream(path: "\(self.methodPath)", headers: headers)
            """
        } else if self.clientStreaming {
            return """
            self.client.clientOnlyStream(path: "\(self.methodPath)", headers: headers)
            """
        } else {
            return """
            await self.client.unary(path: "\(self.methodPath)", request: request, headers: headers)
            """
        }
    }
}
