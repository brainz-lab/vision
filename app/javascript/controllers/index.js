// Import and register all controllers from the controllers directory

import { application } from "controllers/application"

// Eager load all controllers defined in the controllers directory
import DarkModeController from "controllers/dark_mode_controller"
application.register("dark-mode", DarkModeController)
