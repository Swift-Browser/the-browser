// Copyright 2026 Medusa. Apache-2.0.

#ifndef CHROME_BROWSER_MEDUSA_AC_CLI_TOKEN_POLICY_H_
#define CHROME_BROWSER_MEDUSA_AC_CLI_TOKEN_POLICY_H_

#include <memory>

#include "medusa/core/ac_content_hooks.h"  // nogncheck

namespace content {
class DevToolsAgentHost;
class DevToolsAgentHostClient;
class RenderFrameHost;
}

namespace medusa {

std::unique_ptr<MedusaDevToolsTokenClient> CreateTokenClient(
    content::DevToolsAgentHostClient* client,
    content::DevToolsAgentHost* host);

bool TokenClientMayAttach(content::DevToolsAgentHostClient* root_client,
                          content::DevToolsAgentHost* host);

bool TokenClientMayInput(content::DevToolsAgentHostClient* root_client,
                         content::RenderFrameHost* frame);

}

#endif
