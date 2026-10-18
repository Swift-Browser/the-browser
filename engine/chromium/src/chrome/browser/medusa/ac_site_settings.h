// Copyright 2026 Medusa. Apache-2.0.

#ifndef CHROME_BROWSER_MEDUSA_AC_SITE_SETTINGS_H_
#define CHROME_BROWSER_MEDUSA_AC_SITE_SETTINGS_H_

#include "chrome/browser/medusa/ac_engine.h"

AC_ENGINE_CALL(ac_site_settings_get);
AC_ENGINE_CALL(ac_site_settings_set);
AC_ENGINE_CALL(ac_site_settings_reset);
AC_ENGINE_CALL(ac_site_settings_origins);
AC_ENGINE_CALL(ac_site_data_clear);

#endif
