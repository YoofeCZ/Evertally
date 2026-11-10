import { logout } from "@/lib/auth";
export const dynamic = "force-dynamic";
export function POST(request: Request) { return logout(request); }
