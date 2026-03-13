import "dotenv/config";
import { z } from "zod";

const configSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(8080),
  GOOGLE_MAPS_API_KEY: z.string().min(1, "GOOGLE_MAPS_API_KEY is required"),
  ALLOWED_ORIGINS: z.string().default("*")
});

const parsed = configSchema.safeParse(process.env);

if (!parsed.success) {
  const reason = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
  throw new Error(`Invalid backend environment: ${reason}`);
}

export const config = parsed.data;
