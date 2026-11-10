import { ProjectPolicies } from "@/components/evertally/ProjectPolicies";

export const metadata = {
  title: "Privacy and data · Evertally",
  description: "How Evertally handles optional game exports, Discord sign-in, public profiles and deletion.",
};

export default function PrivacyPage() {
  return <ProjectPolicies page="privacy" />;
}
