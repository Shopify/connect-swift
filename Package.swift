// swift-tools-version:5.6

// Copyright 2022-2023 Buf Technologies, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import PackageDescription

let package = Package(
    name: "Connect",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "Connect",
            targets: ["Connect"]
        ),
		.library(
			name: "ConnectMocks",
			targets: ["ConnectMocks"]
		),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            from: "1.25.2"
        ),
    ],
    targets: [
        .target(
            name: "Connect",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Libraries/Connect",
            exclude: [
                "buf.gen.yaml",
                "proto",
                "README.md",
            ]
        ),
		.target(
			name: "ConnectMocks",
			dependencies: [
				.target(name: "Connect"),
				.product(name: "SwiftProtobuf", package: "swift-protobuf"),
			],
			path: "Libraries/ConnectMocks",
			exclude: [
				"README.md",
			]
		),
    ],
    swiftLanguageVersions: [.v5]
)
