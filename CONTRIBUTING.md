# Overview

Hi, if youve made it to this doc you likely want to submit an issue, suggestion, or pr to conpositor without causing issues for other people involved. Thanks for your concern. This document will lay down some basic rules I go by for moderation. I will try to keep this document up to date with most hard rules I maintain. However please note I (prestosilver) will still get the final say in disputes.

# Bug reports

As the project is still starting informal bug reports are fine, please include as much info as possible. If you can track the bug down that will help alot and increase the chances it will be looked into soon. Once the project starts becoming more nuanced I will work on introducing a more formal bug report system. That said, documentation bugs may be closed until the project ages a bit more as this is a focus of the first few updates after 1.0.0.

This is mainly to increase incoming bugs, I find it quite important to make things like bug reports easy until they are clearly too easy.

# Feature requests

When you submit a feature request for conpositor please make sure it hasnt already been proposed with a quick search of the issue tracker. All features should be made in github issues, they will then be tagged with the `enhancement` tag. After some discussion I will eventually mark it with the `accepted` tag. Breaking changes must also be taged with `breaking`.

## Parent vs blocking issues

Child issues in conpositor will be considered anything that is part of another issue, even if that means a blocking part. While blocking means that the issue cannot gain the `accepted` tag until the other is resolved. This means `accepted` issues cannot block issues.

# Pull requests

When you submit a PR to conpositor there is only one way to guarantee its merging, please make a draft pr for an issue. If you submit a pr for an issue assigned to noone I will likely review and work on merging it, but if its assigned itll likely need to be resolved case by case. I likely wont be too strict with this early on, if the project gathers signifigant contributers however I will need to be stricter. Really just dont try to "be cool" by beating someone to an issue.

## Code style

Every .zig file should contain notes for implementation contracts at the top, make sure you follow those at the very least. As of right now itll likely endup being me who reviews your code.

Please format with zig-fmt, and abide by the https://ziglang.org/documentation/master/#Style-Guide. I will comment if theres anything that nags me. As with many other places in this doc, I plan to mature this spec with conpositor.