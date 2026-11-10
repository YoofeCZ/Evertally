import { startDiscordLogin } from "@/lib/auth";
export const dynamic = "force-dynamic";
export function GET(request: Request) { return startDiscordLogin(request); }
