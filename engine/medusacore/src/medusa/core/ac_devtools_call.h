// Copyright 2026 Medusa. Apache-2.0.

#ifndef MEDUSA_CORE_AC_DEVTOOLS_CALL_H_
#define MEDUSA_CORE_AC_DEVTOOLS_CALL_H_

#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "base/time/time.h"
#include "base/values.h"

namespace content {
class WebContents;
}

namespace medusacore {

using DevToolsReply = base::OnceCallback<void(std::optional<base::DictValue> result,
                                              std::optional<std::string> error)>;
void CallDevTools(content::WebContents* contents,
                  const std::string& method,
                  base::DictValue params,
                  std::optional<base::TimeDelta> timeout,
                  DevToolsReply reply);

}

#endif
