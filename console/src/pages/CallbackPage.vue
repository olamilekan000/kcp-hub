<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import * as oidc from '@/lib/oidc'
import { useSession } from '@/stores/session'
import Spinner from '@/components/Spinner.vue'

const router = useRouter()
const session = useSession()
const error = ref('')

onMounted(async () => {
  try {
    await oidc.complete(window.location.search)
    session.claims = oidc.claims()
    await session.load()
    await session.checkAdmin()
    // Signing in without a particular page in mind, and with no project to
    // work in yet, is the first run: the wizard is the useful place to land.
    const target = oidc.returnTo()
    router.replace(target === '/' && session.nothingToWorkIn ? { name: 'welcome' } : target)
  } catch (e) {
    error.value = e instanceof Error ? e.message : String(e)
  }
})
</script>

<template>
  <div class="min-h-screen grid place-items-center px-6">
    <div v-if="!error" class="text-xs text-muted flex items-center gap-2" role="status">
      <Spinner />
      Signing you in…
    </div>
    <div v-else class="w-full max-w-sm">
      <p class="k-note k-note--danger">{{ error }}</p>
      <RouterLink to="/login" class="mt-4 inline-block text-xs text-accent">Try again</RouterLink>
    </div>
  </div>
</template>
