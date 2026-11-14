import { handleApi } from "@/lib/api";
export const dynamic = "force-dynamic";
export function GET(request: Request) { return handleApi(request, "pairing"); }
export function POST(request: Request) { return handleApi(request, "pairing"); }
