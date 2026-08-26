// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "CreditCardRewardLogic",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "CreditCardRewardLogic", targets: ["CreditCardRewardLogic"]),
    ],
    targets: [
        .target(
            name: "CreditCardRewardLogic",
            resources: [
                .copy("Resources/cube_reward_rules.json"),
                .copy("Resources/jiho_reward_rules.json"),
                .copy("Resources/merchants.json"),
            ]
        ),
        .testTarget(
            name: "CreditCardRewardLogicTests",
            dependencies: ["CreditCardRewardLogic"]
        ),
    ]
)
